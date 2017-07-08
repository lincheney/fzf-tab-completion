extern crate regex;
use regex::Regex;

pub struct Match {
    pub start: usize,
    pub end: usize,
    pub found: bool,
}

fn parse_line(line: &str, point: usize) -> Match {
    let i = 0;
    let start: Option<usize> = None;

    let start = Some(0);
    let i = line.len();

    let start = start.unwrap_or(i);
    Match{start: start, end: i, found: 0 < point && point <= i}
}

fn main() {
    println!("Hello, world!");
}

#[cfg(test)]
mod test {
    use super::parse_line;

    fn assert_parse_line(line: &str, expected: &str) {
        let point = line.find('_').unwrap();
        let (left, right) = line.split_at(point);
        let line = String::new() + left + &right[1..];

        let m = parse_line(&line, point);
        assert_eq!( &line[m.start..m.end], expected );
    }

    #[test]
    fn test_parse_line() {
        assert_parse_line("echo_ 123", "echo 123");
        assert_parse_line(" echo_ 123", "echo 123");
        assert_parse_line("if echo_ 123", "echo 123");
        assert_parse_line("when echo_ 123", "echo 123");
    }
}
