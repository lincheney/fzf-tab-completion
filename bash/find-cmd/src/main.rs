#[macro_use] extern crate lazy_static;
extern crate regex;
use regex::Regex;
use std::env;

#[derive(Debug)]
pub struct Match<'a> {
    pub start: usize,
    pub end: usize,
    pub found: bool,
    pub tokens: Vec<&'a str>,
    pub index: usize,
    pub sindex: usize,
}

impl<'a> Match<'a> {
    pub fn offset(self, offset: usize, index: usize) -> Match<'a> {
        Match{
            start: self.start+offset,
            end: self.end+offset,
            found: self.found,
            tokens: self.tokens,
            index: self.index+index,
            sindex: self.sindex,
        }
    }
}

lazy_static! {
    static ref DQ_STRING_RE: Regex = Regex::new(concat!(r"^((\\.|(\$\{[^}]*})|(\$($|[^(]))|", "[^\"$])+|\"|\\$\\()")).unwrap();
    static ref CURLY_VAR_RE: Regex = Regex::new(r"^\$\{[^}]*($|})").unwrap();
    static ref WHITESPACE_RE: Regex = Regex::new(r"^([\s&&[^\n]]|\\\n)+").unwrap(); // newlines split statements
    static ref KEYWORD_RE: Regex = Regex::new(r"^(\[\[|case|do|done|elif|else|esac|fi|for|function|if|in|select|then|time|until|while)\s").unwrap();
    static ref NEW_STATEMENT_RE: Regex = Regex::new(r"^(;|\n|&&|\|[|&]?)").unwrap();
    static ref ENV_VAR_RE: Regex = Regex::new(r"^\w+=").unwrap();
    static ref TOKEN_RE: Regex = Regex::new(concat!(
            r"^(",
            r"('[^']*('|$))|", // ' string
            r"(\$'(\\.|[^'])*('|$))|", // $' string
            "(\\\\.|[^;\\s'\"(){}`])+", // other
            r")",
    )).unwrap();
    static ref CLOSE_ROUND_BRACKET_RE: Regex = Regex::new(r"^\)").unwrap();
    static ref CLOSE_CURLY_BRACKET_RE: Regex = Regex::new(r"^\}").unwrap();
    static ref BACKTICK_RE: Regex = Regex::new(r"^`").unwrap();
}

fn parse_dq_string<'a>(line: &'a str, point: usize) -> Match<'a> {
    let mut i = 0;
    while i < line.len() {
        match DQ_STRING_RE.find(&line[i..]).unwrap().as_str() {
            "$(" => {
                i += 2;
                let m = parse_line(&line[i..], if point<i { 0 } else { point-i }, Some(&CLOSE_ROUND_BRACKET_RE));
                if m.found { return m.offset(i, 0); }
                i += m.end;
            },
            "\"" => { i += 1; break; },
            x => { i += x.len(); },
        }
    }
    return Match{start: 0, end: i, found: false, tokens: vec![line], index: 0, sindex: 0};
}

fn parse_line<'a>(line: &'a str, point: usize, end: Option<&Regex>) -> Match<'a> {
    let mut i = 0;
    let mut start: Option<usize> = None;
    let mut tokens: Vec<&str> = vec![];
    let mut index = 0;
    let mut sindex: Option<usize> = None;

    while i < line.len() {
        if let Some(end) = end {
            if end.is_match(&line[i..]) {
                break;
            }
        }

        if point <= i && sindex.is_none() {
            sindex = Some(match tokens.last().unwrap_or(&"").len() {
                0 => 0,
                l => l + point - i,
            });
        }

        if let Some(m) = WHITESPACE_RE.find(&line[i..]) {
            i += m.end();
            tokens.push(""); // force empty string to be added to tokens as a separator
            continue;
        }

        if point <= i && index == 0 {
            index = tokens.iter().filter(|t| ! t.is_empty()).count();
            if point == i { index += 1 };
        }

        start = start.or(Some(i));

        if line[i..].starts_with('"') {
            let mut oldi = i;
            i += 1;
            let m = parse_dq_string(&line[i..], if point<i { 0 } else { point-i });
            if m.found { return m.offset(i, index); }
            i += m.end;

            if ! tokens.last().unwrap_or(&"").is_empty() {
                oldi -= tokens.pop().unwrap().len();
            }
            tokens.push(&line[oldi..i]);
            continue;
        }

        if let Some(m) = CURLY_VAR_RE.find(&line[i..]) {
            i += m.end();
            tokens.push(&line[i-m.end()..i]);
            continue;
        }

        let mut matched = false;
        for &(open, close) in [
                ('(', &CLOSE_ROUND_BRACKET_RE as &Regex),
                ('{', &CLOSE_CURLY_BRACKET_RE),
                ('`', &BACKTICK_RE),
        ].iter() {
            if line[i..].starts_with(open) {
                let mut oldi = i;
                i += 1;
                let m = parse_line(&line[i..], if point<i { 0 } else { point-i }, Some(close));
                if m.found { return m.offset(i, 0); }
                if i == point {
                    return Match{ start: i, end: i+m.end, found: true, tokens: m.tokens, index: index+1, sindex: 0 };
                }
                i += m.end;
                if i+1 < line.len() { i += 1; }

                if ! tokens.last().unwrap_or(&"").is_empty() {
                    oldi -= tokens.pop().unwrap().len();
                }
                matched = true;
                tokens.push(&line[oldi..i]);
                break;
            }
        }
        if matched { continue; }

        if start == Some(i) {
            if let Some(m) = KEYWORD_RE.find(&line[i..]) {
                let oldi = i;
                i += m.end();
                if i > point {
                    i -= 1;
                    tokens.push(&line[oldi..i]);
                    break;
                }
                start = None;
                tokens.clear();
                continue;
            }
            if let Some(m) = ENV_VAR_RE.find(&line[i..]) {
                i += m.end();
                let m = parse_line(&line[i..], if point<i { 0 } else { point-i }, Some(&WHITESPACE_RE));
                if i >= point || (m.found && m.start == 0) {
                    let start = start.unwrap();
                    let end = m.end + i;
                    let sindex = point - start;
                    return Match{ start: start, end: end, found: true, tokens: vec![&line[start..end]], index: 1, sindex: sindex };
                }
                if m.found { return m.offset(i, 0); }
                i += m.end;
                start = None;
                tokens.clear();
                continue;
            }
        }

        if let Some(m) = NEW_STATEMENT_RE.find(&line[i..]) {
            if i > point { break; }
            start = None;
            i += m.end();
            tokens.clear();
            continue;
        }

        if let Some(m) = TOKEN_RE.find(&line[i..]) {
            let mut oldi = i;
            i += m.end();

            if ! tokens.last().unwrap_or(&"").is_empty() {
                oldi -= tokens.pop().unwrap().len();
            }
            tokens.push(&line[oldi..i]);
            continue;
        }

        i += 1; // fallback
        tokens.push(&line[i..i-1]);
    }

    if point <= i && sindex.is_none() {
        sindex = Some(match tokens.last().unwrap_or(&"").len() {
            0 => 0,
            l => l + point - i,
        });
    }

    let start = start.unwrap_or(i);
    let sindex = sindex.unwrap_or(0);
    let tokens: Vec<&str> = tokens.into_iter().filter(|t| ! t.is_empty()).collect();

    if point <= i && index == 0 {
        index = tokens.len();
    }

    // let index = tokens.len();
    Match{start: start, end: i, found: 0 < point && point <= i, tokens: tokens, index: index, sindex: sindex}
}

fn main() {
    let line = env::var("READLINE_LINE").expect("expected $READLINE_LINE");
    let point = usize::from_str_radix(&env::var("READLINE_POINT").expect("expected $READLINE_POINT"), 10).expect("expected uint for $READLINE_POINT");
    let m = parse_line(&line, point, None);
    println!("{} {} {} {}", m.start, m.end, m.index, m.sindex);
    for t in m.tokens {
        println!("{}", t);
    }
}

#[cfg(test)]
mod test {
    use super::parse_line;

    macro_rules! assert_parse_line {
        ($name:ident, $left:expr, $right:expr, $expected:expr, $array:expr, $index:expr, $sindex:expr) => {
            #[test]
            fn $name() {
                let line = concat!($left, $right);
                println!("{:?}", line);
                let m = parse_line(&line, $left.len(), None);
                assert_eq!( &line[m.start..m.end], $expected, "checking start,end" );
                assert_eq!( m.tokens, $array, "checking tokens" );
                assert_eq!( m.index, $index, "checking index" );
                assert_eq!( m.sindex, $sindex, "checking sindex" );
            }
        }
    }

    assert_parse_line!(test_1, "", "", "", Vec::<&str>::new(), 0, 0);
    assert_parse_line!(test_21, "echo ; ", "", "", Vec::<&str>::new(), 0, 0);
    assert_parse_line!(test_22, "echo 123", "", "echo 123", vec!["echo", "123"], 2, 3);

    assert_parse_line!(test_31, "echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_32, "echo 123 ", "", "echo 123 ", vec!["echo", "123"], 2, 0);
    assert_parse_line!(test_33, " echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_34, "echo \\\n", " 123", "echo \\\n 123", vec!["echo", "123"], 1, 0);
    assert_parse_line!(test_35, "ec", "ho", "echo", vec!["echo"], 1, 2);

    assert_parse_line!(test_411, "echo ", "\"123\"", "echo \"123\"", vec!["echo", "\"123\""], 2, 0);
    assert_parse_line!(test_412, "echo ", "\"123", "echo \"123", vec!["echo", "\"123"], 2, 0);
    assert_parse_line!(test_413, "echo ", "\"12$(cat)3\"", "echo \"12$(cat)3\"", vec!["echo", "\"12$(cat)3\""], 2, 0);
    assert_parse_line!(test_414, "echo ", "12$(cat file)3", "echo 12$(cat file)3", vec!["echo", "12$(cat file)3"], 2, 0);
    assert_parse_line!(test_415, "echo \"12$(ca", "t)3\"", "cat", vec!["cat"], 1, 2);
    assert_parse_line!(test_416, "echo \"12$(ca", "t file)3\"", "cat file", vec!["cat", "file"], 1, 2);
    assert_parse_line!(test_417, "echo \"12$ca", "t3\"", "echo \"12$cat3\"", vec!["echo", "\"12$cat3\""], 2, 6);
    assert_parse_line!(test_42, "echo \"as$", "", "echo \"as$", vec!["echo", "\"as$"], 2, 4);
    assert_parse_line!(test_431, "echo", " '12(3'", "echo '12(3'", vec!["echo", "'12(3'"], 1, 4);
    assert_parse_line!(test_432, "echo", " '12(3", "echo '12(3", vec!["echo", "'12(3"], 1, 4);
    assert_parse_line!(test_433, "echo", " $'12\\'3'", "echo $'12\\'3'", vec!["echo", "$'12\\'3'"], 1, 4);
    assert_parse_line!(test_434, "echo", " '1\\'2\\\\(3'", "echo '1\\'2\\\\(3'", vec!["echo", "'1\\'2\\\\(3'"], 1, 4);
    assert_parse_line!(test_44, "`cat`; echo", "", "echo", vec!["echo"], 1, 4);

    assert_parse_line!(test_51, "[[ echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_52, "case echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_53, "do echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_54, "done echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_55, "elif echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_56, "else echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_57, "esac echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_58, "fi echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_59, "for echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_5a, "function echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_5b, "if echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_5c, "in echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_5d, "select echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_5e, "then echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_5f, "time echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_5g, "until echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_5h, "while echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_5i, "whil", "e echo 123", "while", vec!["while"], 1, 4);

    assert_parse_line!(test_61, "echo", " 123 ; echo 456", "echo 123 ", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_62, "echo 123 ; echo", " 456", "echo 456", vec!["echo", "456"], 1, 4);
    assert_parse_line!(test_63, "echo", " 123; echo 456", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_64, "echo 123; echo", " 456", "echo 456", vec!["echo", "456"], 1, 4);
    assert_parse_line!(test_65, "echo", " 123 \n echo 456", "echo 123 ", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_66, "echo 123 \n echo", " 456", "echo 456", vec!["echo", "456"], 1, 4);
    assert_parse_line!(test_67, "echo", " 123 && echo 456", "echo 123 ", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_68, "echo 123 && echo", " 456", "echo 456", vec!["echo", "456"], 1, 4);
    assert_parse_line!(test_69, "echo", " 123 || echo 456", "echo 123 ", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_6a, "echo 123 || echo", " 456", "echo 456", vec!["echo", "456"], 1, 4);
    assert_parse_line!(test_6b, "echo", " 123 | echo 456", "echo 123 ", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_6c, "echo 123 | echo", " 456", "echo 456", vec!["echo", "456"], 1, 4);
    assert_parse_line!(test_6d, "echo", " 123 |& echo 456", "echo 123 ", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_6e, "echo 123 |& echo", " 456", "echo 456", vec!["echo", "456"], 1, 4);

    assert_parse_line!(test_71, "echo ${var", "}", "echo ${var}", vec!["echo", "${var}"], 2, 5);
    assert_parse_line!(test_72, "echo ${var", "", "echo ${var", vec!["echo", "${var"], 2, 5);
    assert_parse_line!(test_73, "echo $(cat) ", "123", "echo $(cat) 123", vec!["echo", "$(cat)", "123"], 3, 0);
    assert_parse_line!(test_74, "echo $(ca", "t) 123", "cat", vec!["cat"], 1, 2);
    assert_parse_line!(test_75, "echo $(", "cat) 123", "cat", vec!["cat"], 1, 0);

    assert_parse_line!(test_81, "KEY=VALUE echo", " 123", "echo 123", vec!["echo", "123"], 1, 4);
    assert_parse_line!(test_82, "KE", "Y=VALUE echo 123", "KEY=VALUE", vec!["KEY=VALUE"], 1, 2);
    assert_parse_line!(test_83, "KEY=VAL", "UE echo 123", "KEY=VALUE", vec!["KEY=VALUE"], 1, 7);
    assert_parse_line!(test_84, "KEY=VA$(ca", "t) echo 123", "cat", vec!["cat"], 1, 2);
    assert_parse_line!(test_85, "KEY=VALUE XYZ=", "STUFF echo 123", "XYZ=STUFF", vec!["XYZ=STUFF"], 1, 4);
    assert_parse_line!(test_86, "KEY=VALUE XYZ=$(ca", "t) echo 123", "cat", vec!["cat"], 1, 2);
    assert_parse_line!(test_87, "KEY=VALUE XYZ=$(ca", "t echo 123", "cat echo 123", vec!["cat", "echo", "123"], 1, 2);
    assert_parse_line!(test_88, "KEY=VALUE XYZ=$(cat)ab", "c echo 123", "XYZ=$(cat)abc", vec!["XYZ=$(cat)abc"], 1, 12);
}
