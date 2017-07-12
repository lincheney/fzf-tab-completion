#[macro_use] extern crate lazy_static;
extern crate regex;
use regex::Regex;
use std::env;

#[derive(Debug)]
pub struct Match {
    pub start: usize,
    pub end: usize,
    pub found: bool,
}

impl Match {
    pub fn offset(&self, x: usize) -> Match {
        Match{ start: self.start+x, end: self.end+x, found: self.found }
    }
}

lazy_static! {
    static ref DQ_STRING_RE: Regex = Regex::new(concat!(r"^((\\.|(\$\{[^}]*})|(\$($|[^(]))|", "[^\"$])+|\"|\\$\\()")).unwrap();
    static ref CURLY_VAR_RE: Regex = Regex::new(r"^\$\{[^}]*($|})").unwrap();
    static ref WHITESPACE_RE: Regex = Regex::new(r"^([\s&&[^\n]]|\\\n)+").unwrap(); // newlines split statements
    static ref KEYWORD_RE: Regex = Regex::new(r"^(\[\[|case|do|done|elif|else|esac|fi|for|function|if|in|select|then|time|until|while)\s").unwrap();
    static ref NEW_STATEMENT_RE: Regex = Regex::new(r"^(;|\n|&&|\|\|)").unwrap();
    static ref ENV_VAR_RE: Regex = Regex::new(r"^\w+=").unwrap();
    static ref TOKEN_RE: Regex = Regex::new(concat!(
            r"^(",
            r"('[^']*('|$))|", // ' string
            r"(\$'(\\.|[^'])*('|$))|", // $' string
            "(\\\\.|[^\\s'\"(){}])+", // other
            r")",
    )).unwrap();
    static ref CLOSE_ROUND_BRACKET_RE: Regex = Regex::new(r"^\)").unwrap();
    static ref CLOSE_CURLY_BRACKET_RE: Regex = Regex::new(r"^\}").unwrap();
}

fn parse_dq_string(line: &str, point: usize) -> Match {
    let mut i = 0;
    while i < line.len() {
        match DQ_STRING_RE.find(&line[i..]).unwrap().as_str() {
            "$(" => {
                i += 2;
                let m = parse_line(&line[i..], if point<i { 0 } else { point-i }, Some(&CLOSE_ROUND_BRACKET_RE));
                if m.found { return m.offset(i); }
                i += m.end;
            },
            "\"" => { i += 1; break; },
            x => { i += x.len(); },
        }
    }
    return Match{start: 0, end: i, found: false};
}

fn parse_line(line: &str, point: usize, end: Option<&Regex>) -> Match {
    let mut i = 0;
    let mut start: Option<usize> = None;

    while i < line.len() {
        if let Some(end) = end {
            if end.is_match(&line[i..]) {
                break;
            }
        }

        if let Some(m) = WHITESPACE_RE.find(&line[i..]) {
            i += m.end();
            continue;
        }

        start = start.or(Some(i));

        if line[i..].starts_with('"') {
            i += 1;
            let m = parse_dq_string(&line[i..], if point<i { 0 } else { point-i });
            if m.found { return m.offset(i); }
            i += m.end;
            continue;
        }

        if let Some(m) = CURLY_VAR_RE.find(&line[i..]) {
            i += m.end();
            continue;
        }

        let block_end = if line[i..].starts_with('(') {
            i += 1;
            Some(&CLOSE_ROUND_BRACKET_RE as &Regex)
        } else if line[i..].starts_with('{') {
            i += 1;
            Some(&CLOSE_CURLY_BRACKET_RE as &Regex)
        } else {
            None
        };

        if block_end.is_some() {
            let m = parse_line(&line[i..], if point<i { 0 } else { point-i }, block_end);
            if m.found { return m.offset(i); }
            i += m.end;
            continue;
        }

        if start == Some(i) {
            if let Some(m) = KEYWORD_RE.find(&line[i..]) {
                i += m.end();
                if i > point {
                    i -= 1;
                    break;
                }
                start = None;
                continue;
            }
            if let Some(m) = ENV_VAR_RE.find(&line[i..]) {
                i += m.end();
                let m = parse_line(&line[i..], if point<i { 0 } else { point-i }, Some(&WHITESPACE_RE));
                if i >= point || (m.found && m.start == 0) {
                    return Match{ start: start.unwrap(), end: m.end+i, found: true };
                }
                if m.found { return m.offset(i); }
                i += m.end;
                start = None;
                continue;
            }
        }

        if let Some(m) = NEW_STATEMENT_RE.find(&line[i..]) {
            if i > point { break; }
            start = None;
            i += m.end();
            continue;
        }

        if let Some(m) = TOKEN_RE.find(&line[i..]) {
            i += m.end();
            continue;
        }

        i += 1; // fallback
    }

    let start = start.unwrap_or(i);
    Match{start: start, end: i, found: 0 < point && point <= i}
}

fn main() {
    let line = env::var("READLINE_LINE").expect("expected $READLINE_LINE");
    let point = usize::from_str_radix(&env::var("READLINE_POINT").expect("expected $READLINE_POINT"), 10).expect("expected uint for $READLINE_POINT");
    let m = parse_line(&line, point, None);
    println!("{} {}", m.start, m.end);
}

#[cfg(test)]
mod test {
    use super::parse_line;

    macro_rules! assert_parse_line {
        ($left:expr, $right:expr, $expected:expr) => {
            let line = concat!($left, $right);
            let m = parse_line(&line, $left.len(), None);
            assert_eq!( &line[m.start..m.end], $expected );
        }
    }

    #[test]
    fn test_parse_line() {
        assert_parse_line!("echo", " 123", "echo 123");
        assert_parse_line!(" echo", " 123", "echo 123");
        assert_parse_line!("echo \\\n", " 123", "echo \\\n 123");

        assert_parse_line!("echo ", "\"123\"", "echo \"123\"");
        assert_parse_line!("echo ", "\"123", "echo \"123");
        assert_parse_line!("echo ", "\"12$(cat)3\"", "echo \"12$(cat)3\"");
        assert_parse_line!("echo \"12$(ca", "t)3\"", "cat");
        assert_parse_line!("echo \"12$ca", "t3\"", "echo \"12$cat3\"");
        assert_parse_line!("echo \"as$", "", "echo \"as$");
        assert_parse_line!("echo", " '12(3'", "echo '12(3'");
        assert_parse_line!("echo", " '12(3", "echo '12(3");
        assert_parse_line!("echo", " $'12\\'3'", "echo $'12\\'3'");
        assert_parse_line!("echo", " '1\\'2\\\\(3'", "echo '1\\'2\\\\(3'");

        assert_parse_line!("[[ echo", " 123", "echo 123");
        assert_parse_line!("case echo", " 123", "echo 123");
        assert_parse_line!("do echo", " 123", "echo 123");
        assert_parse_line!("done echo", " 123", "echo 123");
        assert_parse_line!("elif echo", " 123", "echo 123");
        assert_parse_line!("else echo", " 123", "echo 123");
        assert_parse_line!("esac echo", " 123", "echo 123");
        assert_parse_line!("fi echo", " 123", "echo 123");
        assert_parse_line!("for echo", " 123", "echo 123");
        assert_parse_line!("function echo", " 123", "echo 123");
        assert_parse_line!("if echo", " 123", "echo 123");
        assert_parse_line!("in echo", " 123", "echo 123");
        assert_parse_line!("select echo", " 123", "echo 123");
        assert_parse_line!("then echo", " 123", "echo 123");
        assert_parse_line!("time echo", " 123", "echo 123");
        assert_parse_line!("until echo", " 123", "echo 123");
        assert_parse_line!("while echo", " 123", "echo 123");
        assert_parse_line!("whil", "e echo 123", "while");

        assert_parse_line!("echo", " 123 ; echo 456", "echo 123 ");
        assert_parse_line!("echo 123 ; echo", " 456", "echo 456");
        assert_parse_line!("echo", " 123 \n echo 456", "echo 123 ");
        assert_parse_line!("echo 123 \n echo", " 456", "echo 456");
        assert_parse_line!("echo", " 123 && echo 456", "echo 123 ");
        assert_parse_line!("echo 123 && echo", " 456", "echo 456");
        assert_parse_line!("echo", " 123 || echo 456", "echo 123 ");
        assert_parse_line!("echo 123 || echo", " 456", "echo 456");

        assert_parse_line!("echo ${var", "}", "echo ${var}");
        assert_parse_line!("echo ${var", "", "echo ${var");
        assert_parse_line!("echo $(cat) ", "123", "echo $(cat) 123");
        assert_parse_line!("echo $(ca", "t) 123", "cat");

        assert_parse_line!("KEY=VALUE echo", " 123", "echo 123");
        assert_parse_line!("KE", "Y=VALUE echo 123", "KEY=VALUE");
        assert_parse_line!("KEY=VAL", "UE echo 123", "KEY=VALUE");
        assert_parse_line!("KEY=VA$(ca", "t) echo 123", "cat");
        assert_parse_line!("KEY=VALUE XYZ=", "STUFF echo 123", "XYZ=STUFF");
        assert_parse_line!("KEY=VALUE XYZ=$(ca", "t) echo 123", "cat");
        assert_parse_line!("KEY=VALUE XYZ=$(ca", "t echo 123", "cat echo 123");
    }
}
