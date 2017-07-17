extern crate shellexpand;
extern crate users;
use std::path::Path;
use std::process::exit;
use std::io::{stdin, stdout, BufRead, Write, Error};
use users::os::unix::UserExt;

fn check_for_dir(string: &str) -> bool {
    // expand tilde
    let mut path;
    let string = if string.starts_with('~') {
        let part = string.find('/').map_or(string, |i| &string[..i]);
        path = match &part[1..] {
            "+" => "${PWD}".to_owned(),
            "-" => "${OLDPWD}".to_owned(),
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
        };
        path.push_str(&string[part.len()..]);
        &path
    } else {
        string
    };

    // expand env vars
    let string = match shellexpand::env(string) {
        Ok(string) => string,
        Err(_) => { return false },
    };

    Path::new(&*string).is_dir()
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
    fn test_tilde_and_var() {
        // tilde gets expanded first
        assert_eq!(check_for_dir("~$USER"), false);
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
        env::set_var("OLDPWD", "/");
        assert_eq!(check_for_dir("~-"), true);
    }
}
