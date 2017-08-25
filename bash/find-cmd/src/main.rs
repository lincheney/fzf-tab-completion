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
}

impl<'a> Match<'a> {
    pub fn offset(self, offset: usize, index: usize) -> Match<'a> {
        Match{ start: self.start+offset, end: self.end+offset, found: self.found, tokens: self.tokens, index: self.index+index }
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
    return Match{start: 0, end: i, found: false, tokens: vec![line], index: 0};
}

fn parse_line<'a>(line: &'a str, point: usize, end: Option<&Regex>) -> Match<'a> {
    let mut i = 0;
    let mut oldi = i;
    let mut start: Option<usize> = None;
    let mut tokens: Vec<&str> = vec![];
    let mut index = 0;

    while i < line.len() {
        tokens.push(&line[oldi..i]);
        oldi = i;

        if let Some(end) = end {
            if end.is_match(&line[i..]) {
                break;
            }
        }

        if let Some(m) = WHITESPACE_RE.find(&line[i..]) {
            i += m.end();
            oldi = i; // force empty string to be added to tokens as a separator
            continue;
        }

        if point <= i && index == 0 {
            index = tokens.iter().filter(|t| ! t.is_empty()).count();
            if point == i { index += 1 };
        }

        start = start.or(Some(i));

        if line[i..].starts_with('"') {
            i += 1;
            let m = parse_dq_string(&line[i..], if point<i { 0 } else { point-i });
            if m.found {
                return m.offset(i, index);
            }
            i += m.end;

            if ! tokens.last().unwrap_or(&"").is_empty() {
                oldi -= tokens.pop().unwrap().len();
            }
            continue;
        }

        if let Some(m) = CURLY_VAR_RE.find(&line[i..]) {
            i += m.end();
            continue;
        }

        let mut matched = false;
        for &(open, close) in [
                ('(', &CLOSE_ROUND_BRACKET_RE as &Regex),
                ('{', &CLOSE_CURLY_BRACKET_RE),
                ('`', &BACKTICK_RE),
        ].iter() {
            if line[i..].starts_with(open) {
                i += 1;
                let m = parse_line(&line[i..], if point<i { 0 } else { point-i }, Some(close));
                if m.found { return m.offset(i, 0); }
                if i == point {
                    return Match{ start: i, end: i+m.end, found: true, tokens: m.tokens, index: index+1 };
                }
                i += m.end;
                if i+1 < line.len() { i += 1; }

                if ! tokens.last().unwrap_or(&"").is_empty() {
                    oldi -= tokens.pop().unwrap().len();
                }
                matched = true;
                break;
            }
        }
        if matched { continue; }

        if start == Some(i) {
            if let Some(m) = KEYWORD_RE.find(&line[i..]) {
                i += m.end();
                if i > point {
                    i -= 1;
                    break;
                }
                start = None;
                oldi = i;
                tokens.clear();
                continue;
            }
            if let Some(m) = ENV_VAR_RE.find(&line[i..]) {
                i += m.end();
                let m = parse_line(&line[i..], if point<i { 0 } else { point-i }, Some(&WHITESPACE_RE));
                if i >= point || (m.found && m.start == 0) {
                    let start = start.unwrap();
                    let end = m.end + i;
                    return Match{ start: start, end: end, found: true, tokens: vec![&line[start..end]], index: 1 };
                }
                if m.found { return m.offset(i, 0); }
                i += m.end;
                start = None;
                oldi = i;
                tokens.clear();
                continue;
            }
        }

        if let Some(m) = NEW_STATEMENT_RE.find(&line[i..]) {
            if i > point { break; }
            start = None;
            i += m.end();
            oldi = i;
            tokens.clear();
            continue;
        }

        if let Some(m) = TOKEN_RE.find(&line[i..]) {
            i += m.end();

            if ! tokens.last().unwrap_or(&"").is_empty() {
                oldi -= tokens.pop().unwrap().len();
            }
            continue;
        }

        i += 1; // fallback
    }
    // println!("{:?} {}", tokens, line.len()-i);
    tokens.push(&line[oldi..i]);

    let start = start.unwrap_or(i);
    let tokens: Vec<&str> = tokens.into_iter().filter(|t| ! t.is_empty()).collect();

    if point <= i && index == 0 {
        index = tokens.iter().filter(|t| ! t.is_empty()).count();
    }

    // let index = tokens.len();
    Match{start: start, end: i, found: 0 < point && point <= i, tokens: tokens, index: index}
}

fn main() {
    let line = env::var("READLINE_LINE").expect("expected $READLINE_LINE");
    let point = usize::from_str_radix(&env::var("READLINE_POINT").expect("expected $READLINE_POINT"), 10).expect("expected uint for $READLINE_POINT");
    let m = parse_line(&line, point, None);
    println!("{} {} {}", m.start, m.end, m.index);
    for t in m.tokens {
        println!("{}", t);
    }
}

#[cfg(test)]
mod test {
    use super::parse_line;

    macro_rules! assert_parse_line {
        ($left:expr, $right:expr, $expected:expr, $array:expr, $index:expr) => {
            let line = concat!($left, $right);
            let m = parse_line(&line, $left.len(), None);
            assert_eq!( &line[m.start..m.end], $expected );
            assert_eq!( m.tokens, $array );
            assert_eq!( m.index, $index );
        }
    }

    #[test]
    fn test_parse_line() {
        assert_parse_line!("", "", "", Vec::<&str>::new(), 0);
        assert_parse_line!("echo ; ", "", "", Vec::<&str>::new(), 0);

        assert_parse_line!("echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("echo 123 ", "", "echo 123 ", vec!["echo", "123"], 2);
        assert_parse_line!(" echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("echo \\\n", " 123", "echo \\\n 123", vec!["echo", "123"], 1);

        assert_parse_line!("echo ", "\"123\"", "echo \"123\"", vec!["echo", "\"123\""], 2);
        assert_parse_line!("echo ", "\"123", "echo \"123", vec!["echo", "\"123"], 2);
        assert_parse_line!("echo ", "\"12$(cat)3\"", "echo \"12$(cat)3\"", vec!["echo", "\"12$(cat)3\""], 2);
        assert_parse_line!("echo ", "12$(cat file)3", "echo 12$(cat file)3", vec!["echo", "12$(cat file)3"], 2);
        assert_parse_line!("echo \"12$(ca", "t)3\"", "cat", vec!["cat"], 1);
        assert_parse_line!("echo \"12$(ca", "t file)3\"", "cat file", vec!["cat", "file"], 1);
        assert_parse_line!("echo \"12$ca", "t3\"", "echo \"12$cat3\"", vec!["echo", "\"12$cat3\""], 2);
        assert_parse_line!("echo \"as$", "", "echo \"as$", vec!["echo", "\"as$"], 2);
        assert_parse_line!("echo", " '12(3'", "echo '12(3'", vec!["echo", "'12(3'"], 1);
        assert_parse_line!("echo", " '12(3", "echo '12(3", vec!["echo", "'12(3"], 1);
        assert_parse_line!("echo", " $'12\\'3'", "echo $'12\\'3'", vec!["echo", "$'12\\'3'"], 1);
        assert_parse_line!("echo", " '1\\'2\\\\(3'", "echo '1\\'2\\\\(3'", vec!["echo", "'1\\'2\\\\(3'"], 1);
        assert_parse_line!("`cat`; echo", "", "echo", vec!["echo"], 1);

        assert_parse_line!("[[ echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("case echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("do echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("done echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("elif echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("else echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("esac echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("fi echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("for echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("function echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("if echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("in echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("select echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("then echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("time echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("until echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("while echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("whil", "e echo 123", "while", vec!["while"], 1);

        assert_parse_line!("echo", " 123 ; echo 456", "echo 123 ", vec!["echo", "123"], 1);
        assert_parse_line!("echo 123 ; echo", " 456", "echo 456", vec!["echo", "456"], 1);
        assert_parse_line!("echo", " 123; echo 456", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("echo 123; echo", " 456", "echo 456", vec!["echo", "456"], 1);
        assert_parse_line!("echo", " 123 \n echo 456", "echo 123 ", vec!["echo", "123"], 1);
        assert_parse_line!("echo 123 \n echo", " 456", "echo 456", vec!["echo", "456"], 1);
        assert_parse_line!("echo", " 123 && echo 456", "echo 123 ", vec!["echo", "123"], 1);
        assert_parse_line!("echo 123 && echo", " 456", "echo 456", vec!["echo", "456"], 1);
        assert_parse_line!("echo", " 123 || echo 456", "echo 123 ", vec!["echo", "123"], 1);
        assert_parse_line!("echo 123 || echo", " 456", "echo 456", vec!["echo", "456"], 1);
        assert_parse_line!("echo", " 123 | echo 456", "echo 123 ", vec!["echo", "123"], 1);
        assert_parse_line!("echo 123 | echo", " 456", "echo 456", vec!["echo", "456"], 1);
        assert_parse_line!("echo", " 123 |& echo 456", "echo 123 ", vec!["echo", "123"], 1);
        assert_parse_line!("echo 123 |& echo", " 456", "echo 456", vec!["echo", "456"], 1);

        assert_parse_line!("echo ${var", "}", "echo ${var}", vec!["echo", "${var}"], 2);
        assert_parse_line!("echo ${var", "", "echo ${var", vec!["echo", "${var"], 2);
        assert_parse_line!("echo $(cat) ", "123", "echo $(cat) 123", vec!["echo", "$(cat)", "123"], 3);
        assert_parse_line!("echo $(ca", "t) 123", "cat", vec!["cat"], 1);
        assert_parse_line!("echo $(", "cat) 123", "cat", vec!["cat"], 1);

        assert_parse_line!("KEY=VALUE echo", " 123", "echo 123", vec!["echo", "123"], 1);
        assert_parse_line!("KE", "Y=VALUE echo 123", "KEY=VALUE", vec!["KEY=VALUE"], 1);
        assert_parse_line!("KEY=VAL", "UE echo 123", "KEY=VALUE", vec!["KEY=VALUE"], 1);
        assert_parse_line!("KEY=VA$(ca", "t) echo 123", "cat", vec!["cat"], 1);
        assert_parse_line!("KEY=VALUE XYZ=", "STUFF echo 123", "XYZ=STUFF", vec!["XYZ=STUFF"], 1);
        assert_parse_line!("KEY=VALUE XYZ=$(ca", "t) echo 123", "cat", vec!["cat"], 1);
        assert_parse_line!("KEY=VALUE XYZ=$(ca", "t echo 123", "cat echo 123", vec!["cat", "echo", "123"], 1);
    }
}
