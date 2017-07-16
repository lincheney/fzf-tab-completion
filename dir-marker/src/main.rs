extern crate shellexpand;
extern crate users;
use std::env;
use std::path::Path;
use std::process::exit;
use std::io::{stdin, stdout, BufRead, Write, Error};
use users::os::unix::UserExt;

fn check_for_dir(string: &str) -> bool {
    // expand env vars
    let expanded = match shellexpand::env(string) {
        Ok(expanded) => expanded,
        Err(_) => { return false },
    };

    // expand tilde
    if string.starts_with('~') {
        let part = expanded.find('/').map_or(&expanded[..], |i| &expanded[..i]);
        let path = match &part[1..] {
            "+" => {
                if let Ok(var) = env::var("PWD") { var } else { return false }
            },
            "-" => {
                if let Ok(var) = env::var("OLDPWD") { var } else { return false }
            },
            "" => {
                users::get_user_by_uid(users::get_current_uid()).unwrap().home_dir().to_str().unwrap().to_owned()
            },
            name => {
                if let Some(user) = users::get_user_by_name(name) {
                    user.home_dir().to_str().unwrap().to_owned()
                } else {
                    return false
                }
            },
        } + &expanded[part.len()..];
        return Path::new(&path).is_dir()
    }

    Path::new(&*expanded).is_dir()
}

fn main_loop() -> Result<(), Error> {
    let stdin = stdin();
    let _stdout = stdout();
    let mut stdout = _stdout.lock();

    for line in stdin.lock().lines() {
        let line = line?;
        stdout.write(line.as_bytes())?;
        if ! line.ends_with('/') && check_for_dir(&line) {
            stdout.write(b"/")?;
        }
        stdout.write(b"\n")?;
    }
    stdout.flush()
}


fn main() {
    exit(match main_loop() {
        Ok(_) => 0,
        Err(_) => 1,
    });
}

#[cfg(test)]
mod test {
    use std::env;
    use users;
    use super::check_for_dir;

    #[test]
    fn test_normal() {
        assert_eq!(check_for_dir("random string"), false);
    }

    #[test]
    fn test_dir() {
        let pwd = env::current_dir().unwrap();
        assert_eq!(check_for_dir(pwd.to_str().unwrap()), true);
    }

    #[test]
    fn test_tilde() {
        assert_eq!(check_for_dir("~/.."), true);
    }

    #[test]
    fn test_tilde_user() {
        let user = users::get_user_by_uid(users::get_current_uid()).unwrap();
        let string = "~".to_string() + user.name();
        assert_eq!(check_for_dir(&string), true);
    }

    #[test]
    fn test_tilde_not_user() {
        assert_eq!(check_for_dir("~askjdh"), false);
    }

    #[test]
    fn test_tilde_not_dir() {
        assert_eq!(check_for_dir("~/random string"), false);
    }

    #[test]
    fn test_env() {
        assert_eq!(check_for_dir("$PWD"), true);
    }

    #[test]
    fn test_env_not_defined() {
        assert_eq!(check_for_dir("$randomvar"), false);
    }

    #[test]
    fn test_pwd() {
        assert_eq!(check_for_dir("~+"), true);
    }

    #[test]
    fn test_oldpwd() {
        assert_eq!(check_for_dir("~-"), true);
    }
}
