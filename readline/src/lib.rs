#[macro_use]
extern crate lazy_static;
extern crate libc;

use std::io::{Write, BufReader, BufRead};
use std::process::{Command, Stdio};
use std::ffi::CStr;

macro_rules! dynlib_call {
    ($func:ident($($args:expr),*)) => {{
        let ptr = {
            use libc::$func;
            $func($($args),*)
        };
        if ptr.is_null() {
            let error = libc::dlerror();
            if error.is_null() {
                Err(concat!("unknown error calling: ", stringify!($func)))
            } else {
                Err(std::ffi::CStr::from_ptr(error).to_str().unwrap())
            }
        } else {
            Ok(ptr)
        }
    }}
}

macro_rules! dlopen {
    ($name:expr) => { dlopen!($name, libc::RTLD_LAZY) };
    ($name:expr, $flags:expr) => { dynlib_call!(dlopen($name.as_ptr() as _, $flags)) };
}

macro_rules! dlsym {
    ($handle:expr, $name:expr) => {
        dlsym!($handle, $name, _)
    };
    ($handle:expr, $name:expr, $type:ty) => {{
        let name = concat!($name, "\0");
        #[allow(clippy::transmute_ptr_to_ptr)]
        dynlib_call!(dlsym($handle, name.as_ptr() as _)).map(|sym|
            std::mem::transmute::<_, $type>(sym)
        )
    }}
}

#[derive(Clone, Copy)]
struct CArray(*const *const i8);

impl Iterator for CArray {
    type Item = *const i8;
    fn next(&mut self) -> Option<*const i8> {
        if self.0.is_null() { return None }
        if unsafe{ *(self.0) }.is_null() { return None }
        let value = unsafe{ &**self.0 };
        // let value = unsafe{ CStr::from_ptr(&**self.ptr) }.to_bytes();
        self.0 = unsafe{ self.0.offset(1) };
        Some(value)
    }
}

fn make_cstr(ptr: *const i8) -> &'static [u8] {
    unsafe{ CStr::from_ptr(ptr) }.to_bytes()
}

mod readline {
    use std::ffi::{CStr, CString};

    #[allow(non_upper_case_globals)]
    static mut original_rl_attempted_completion_function: Option<lib::rl_completion_func_t> = None;

    pub fn refresh_line() {
        unsafe{ lib::rl_refresh_line(0, 0) };
    }

    pub fn get_readline_name() -> Option<&'static str> {
        if lib::rl_readline_name.is_null() {
            None
        } else {
            unsafe{ CStr::from_ptr(lib::rl_readline_name.ptr()) }.to_str().ok()
        }
    }

    pub fn hijack_completion(ignore: isize, key: isize, new_function: lib::rl_completion_func_t) -> isize {
        unsafe {
            original_rl_attempted_completion_function = Some(*lib::rl_attempted_completion_function.ptr());
            lib::rl_attempted_completion_function.set(new_function);
            let value = lib::rl_complete(ignore, key);
            if let Some(func) = original_rl_attempted_completion_function.take() {
                lib::rl_attempted_completion_function.set(func);
            }
            value
        }
    }

    pub fn vec_to_c_array(mut vec: Vec<String>) -> *const *const i8 {
        if vec.is_empty() {
            return std::ptr::null();
        }
        // make array of pointers
        let mut array: Vec<*const i8> = vec.iter_mut().map(|s| {
            s.push('\0');
            s.as_ptr() as *const _
        }).collect();
        array.push(std::ptr::null());
        array.shrink_to_fit();

        let ptr = array.as_ptr();

        // drop ref to data to avoid gc
        std::mem::forget(vec);
        std::mem::forget(array);
        ptr
    }

    pub fn get_completions(text: *const i8, start: isize, end: isize) -> *const *const i8 {
        unsafe {
            let matches = if let Some(func) = original_rl_attempted_completion_function {
                func(text, start, end)
            } else {
                std::ptr::null()
            };

            if matches.is_null() {
                let func = if lib::rl_completion_entry_function.is_null() {
                    *lib::rl_filename_completion_function as _
                } else {
                    *lib::rl_completion_entry_function.ptr()
                };
                lib::rl_completion_matches(text, func)
            } else {
                matches
            }
        }
    }

    pub fn free_match_list(matches: *const *const i8) {
        for line in ::CArray(matches) {
            unsafe{ libc::free(line as *mut libc::c_void) };
        }
        unsafe{ libc::free(matches as *mut libc::c_void) };
    }

    pub fn ignore_completion_duplicates() -> bool {
        *lib::rl_ignore_completion_duplicates > 0
    }

    pub fn filename_completion_desired() -> bool {
        *lib::rl_filename_completion_desired > 0
    }

    pub fn mark_directories() -> bool {
        let value = unsafe{ lib::rl_variable_value(b"mark-directories\0".as_ptr() as _) };
        !value.is_null() && (unsafe{ CStr::from_ptr(value) }).to_bytes() == b"on"
    }

    pub fn tilde_expand(string: &str) -> Result<String, std::str::Utf8Error> {
        let string = CString::new(string).unwrap();
        let ptr = string.as_ptr();
        let value = unsafe{ CStr::from_ptr(lib::tilde_expand(ptr)) }.to_bytes();
        std::str::from_utf8(value).map(|s| s.to_owned())
    }

    #[allow(non_upper_case_globals, non_camel_case_types)]
    mod lib {
        use std::marker::PhantomData;
        pub type rl_completion_func_t = extern fn(*const i8, isize, isize) -> *const *const i8;
        pub type rl_compentry_func_t = unsafe extern fn(*const i8, isize) -> *const i8;

        pub struct Pointer<T>(usize, PhantomData<T>);
        impl<T> Pointer<T> {
            pub fn new(ptr: *mut T)    -> Self { Self(ptr as _, PhantomData) }
            pub fn is_null(&self)      -> bool { self.0 == 0 }
            pub fn ptr(&self)        -> *mut T { self.0 as *mut T }
            pub unsafe fn set(&self, value: T) { *self.ptr() = value; }
        }

        lazy_static! {
            static ref libreadline: Pointer<libc::c_void> = Pointer::new(unsafe{ dlopen!(b"libreadline.so\0") }.unwrap());
        }
        macro_rules! readline_lookup {
            ($name:ident: $type:ty) => {
                lazy_static! { pub static ref $name: $type = unsafe{ dlsym!(libreadline.ptr(), stringify!($name)) }.unwrap(); }
            }
        }

        readline_lookup!(rl_refresh_line:                  unsafe extern fn(isize, isize) -> isize);
        readline_lookup!(rl_completion_matches:            unsafe extern fn(*const i8, rl_compentry_func_t) -> *const *const i8);
        readline_lookup!(rl_variable_value:                unsafe extern fn(*const i8) -> *const i8);
        readline_lookup!(rl_readline_name:                 Pointer<i8>);
        readline_lookup!(tilde_expand:                     unsafe extern fn(*const i8) -> *const i8);
        readline_lookup!(rl_filename_completion_function:  rl_compentry_func_t);
        readline_lookup!(rl_complete:                      unsafe extern fn(isize, isize) -> isize);
        readline_lookup!(rl_ignore_completion_duplicates:  isize);
        readline_lookup!(rl_filename_completion_desired:   isize);

        readline_lookup!(rl_attempted_completion_function: Pointer<rl_completion_func_t>);
        readline_lookup!(rl_completion_entry_function:     Pointer<rl_compentry_func_t>);
    }
}

#[no_mangle]
pub extern fn rl_custom_function(ignore: isize, key: isize) -> isize {
    readline::hijack_completion(ignore, key, custom_complete)
}

extern fn custom_complete(text: *const i8, start: isize, end: isize) -> *const *const i8 {
    let matches = readline::get_completions(text, start, end);

    if let Some(value) = _custom_complete(text, matches) {
        readline::free_match_list(matches);
        readline::vec_to_c_array(value)
    } else {
        matches as *const *const i8
    }
}

fn _custom_complete(text: *const i8, matches: *const *const i8) -> Option<Vec<String>> {
    let text = unsafe{ CStr::from_ptr(text as *const i8) }.to_bytes();
    let text = std::str::from_utf8(text).unwrap();

    let mut command = Command::new("rl_custom_complete");
    command.stdin(Stdio::piped()).stdout(Stdio::piped());
    command.arg(text);

    // pass the readline name to process
    if let Some(name) = readline::get_readline_name() {
        command.env("READLINE_NAME", name);
    }

    let mut process = match command.spawn() {
        Ok(process) => process,
        // failed to run, do default completion
        Err(_) => { return None },
    };
    let mut stdin = process.stdin.unwrap();

    let matches = CArray(matches);
    let length = matches.count();
    let skip = if length == 1 { 0 } else { 1 };
    let mut matches: Vec<_> = matches
        .skip(skip)
        .map(make_cstr)
        .filter_map(|l| std::str::from_utf8(l).ok())
        .filter(|l| !l.is_empty())
        .collect();

    if readline::ignore_completion_duplicates() {
        matches.sort();
        matches.dedup();
    }

    let append_slash = readline::filename_completion_desired() && readline::mark_directories();

    for line in matches {
        // break on errors (but otherwise ignore)
        if stdin.write_all(line.as_bytes()).is_err() {
            break
        }

        if append_slash {
            if let Ok(line) = readline::tilde_expand(line) {
                match std::fs::metadata(line) {
                    Ok(ref f) if f.is_dir() => if stdin.write_all(b"/").is_err() {
                        break
                    }
                    _ => (),
                }
            }
        }
        if stdin.write_all(b"\n").is_err() {
            break
        }
    }

    // pass back stdin for process to close
    process.stdin = Some(stdin);
    match process.wait() {
        // failed to run, do default completion
        Err(_) => {
            None
        },
        // exited with code != 0, leave line as is
        Ok(code) if ! code.success() => {
            readline::refresh_line();
            Some(vec![])
        },
        Ok(_) => {
            readline::refresh_line();
            let stdout = process.stdout.unwrap();
            // readline multi completion doesn't play nice
            // join by spaces here and insert as one value instead
            let vec: Vec<_> = BufReader::new(stdout).lines().map(|l| l.unwrap()).collect();
            let string = vec.join(" ");
            Some(vec![string])
        }
    }
}
