extern crate regex;
use regex::Regex;

#[derive(Debug)]
pub struct Match {
    pub start: usize,
    pub end: usize,
    pub found: bool,
}

fn parse_dq_string(line: &str, point: usize) -> Match {
    let mut i = 0;
    let re = Regex::new(concat!(r"^((\\.|(\$\{[^}]*})|", "[^\"$])+|\"|\\$\\()")).unwrap();
    while i < line.len() {
        match re.find(&line[i..]).unwrap().as_str() {
            "$(" => {
                i += 2;
                let m = parse_line(&line[i..], if point<i { 0 } else { point-i }, Some(")"));
                if m.found {
                    return Match{start: i+m.start, end: i+m.end, found: m.found};
                }
                i += m.end;
            },
            "\"" => { i += 1; break; },
            x => { i += x.len(); },
        }
    }
    return Match{start: 0, end: i, found: false};
}

fn parse_line(line: &str, point: usize, end: Option<&str>) -> Match {
    let mut i = 0;
    let mut start: Option<usize> = None;

    while i < line.len() {
        if let Some(m) = Regex::new(r"^[ \t]+").unwrap().find(&line[i..]) {
            i += m.end();
            continue;
        }

        start = start.or(Some(i));

        match line[i..].chars().next().unwrap() {
            '"' => {
                i += 1;
                let m = parse_dq_string(&line[i..], if point<i { 0 } else { point-i });
                if m.found {
                    return Match{start: i+m.start, end: i+m.end, found: m.found};
                }
                i += m.end;
                continue;
            },
            '\\' => {
                i += 2;
                continue;
            },
            _ => (),
        }

        let block_end = if line[i..].starts_with('(') {
            i += 1;
            Some(")")
        } else if line[i..].starts_with('{') {
            i += 1;
            Some("}")
        } else {
            None
        };

        if block_end.is_some() {
            let m = parse_line(&line[i..], if point<i { 0 } else { point-i }, block_end);
            if m.found {
                return Match{start: i+m.start, end: i+m.end, found: m.found};
            }
            i += m.end;
            continue;
        }

        if let Some(end) = end {
            if line[i..].starts_with(end) {
                break;
            }
        }

        if let Some(m) = Regex::new(r"^'[^']*('|$)").unwrap().find(&line[i..]) {
            // ' string
            i += m.end();
            continue;
        }
        if let Some(m) = Regex::new(r"^\$'(\\.|[^'])*('|$)").unwrap().find(&line[i..]) {
            // $' string
            i += m.end();
            continue;
        }

        if start == Some(i) {
            let regex = Regex::new(r"^(\[\[|case|do|done|elif|else|esac|fi|for|function|if|in|select|then|time|until|while)\s").unwrap();
            if let Some(m) = regex.find(&line[i..]) {
                start = None;
                i += m.end();
                if i > point {
                    i -= 1;
                    break;
                }
                continue;
            }
        }

        if let Some(m) = Regex::new(r"^(;|\n|&&|\|\|)").unwrap().find(&line[i..]) {
            if i > point { break; }
            start = None;
            i += m.end();
            continue;
        }

        i += 1;
    }

    let start = start.unwrap_or(i);
    Match{start: start, end: i, found: 0 < point && point <= i}
}

fn main() {
    println!("Hello, world!");
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

        assert_parse_line!("echo ", "\"123\"", "echo \"123\"");
        assert_parse_line!("echo ", "\"12$(cat)3\"", "echo \"12$(cat)3\"");
        assert_parse_line!("echo \"12$(ca", "t)3\"", "cat");
        assert_parse_line!("echo", " '12(3'", "echo '12(3'");
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

        assert_parse_line!("echo", " 123 ; echo 456", "echo 123 ");
        assert_parse_line!("echo 123 ; echo", " 456", "echo 456");
        assert_parse_line!("echo", " 123 \n echo 456", "echo 123 ");
        assert_parse_line!("echo 123 \n echo", " 456", "echo 456");
        assert_parse_line!("echo", " 123 && echo 456", "echo 123 ");
        assert_parse_line!("echo 123 && echo", " 456", "echo 456");
        assert_parse_line!("echo", " 123 || echo 456", "echo 123 ");
        assert_parse_line!("echo 123 || echo", " 456", "echo 456");

        assert_parse_line!("echo $(cat) ", "123", "echo $(cat) 123");
        assert_parse_line!("echo $(ca", "t) 123", "cat");
    }
}
