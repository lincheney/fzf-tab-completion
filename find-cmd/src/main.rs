fn main() {
    println!("Hello, world!");
}

#[cfg(test)]
mod test {
    use super::parse_line;

    fn assert_parse_line(line: &str, point: usize, expected: &str) {
        let cmd = parse_line(line, point);
        assert_eq!( &line[cmd.start..cmd.end], expected );
    }

    #[test]
    fn test_parse_line() {
        assert_parse_line("echo 123", 1, "echo 123");
    }
}
