#[macro_use]
extern crate lazy_static;
extern crate libc;

use std::io::{Write, BufReader, BufRead};
use std::process::{Command, Stdio};
use std::ffi::CStr;

type DynlibResult<T> = Result<T, &'static str>;

macro_rules! dump_error {
    ($result:expr, $default:expr) => {
        match $result {
            Ok(x) => x,
            Err(e) => { eprintln!("{}", e); return $default },
        }
    }
}

macro_rules! dynlib_call {
    ($func:ident($($args:expr),*)) => {{
        let ptr = libc::$func($($args),*);
        if ptr.is_null() {
            let error = ::libc::dlerror();
            if error.is_null() {
                Err(concat!("unknown error calling: ", stringify!($func)))
            } else {
                Err(::std::ffi::CStr::from_ptr(error).to_str().unwrap())
            }
        } else {
            Ok(ptr)
        }
    }}
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
        if self.0.is_null() || unsafe{ *(self.0) }.is_null() {
            None
        } else {
            let value = unsafe{ &**self.0 };
            self.0 = unsafe{ self.0.offset(1) };
            Some(value)
        }
    }
}

fn make_cstr(ptr: *const i8) -> &'static [u8] {
    unsafe{ CStr::from_ptr(ptr) }.to_bytes()
}

mod readline {
    use std::ffi::{CStr, CString};

    #[allow(non_upper_case_globals)]
    static mut original_rl_attempted_completion_function: Option<lib::rl_completion_func_t> = None;
    #[allow(non_upper_case_globals)]
    static mut original_rl_completion_entry_function: Option<lib::rl_compentry_func_t> = None;

    pub fn refresh_line() -> ::DynlibResult<()> {
        unsafe{ (*lib::rl_refresh_line)?(0, 0) };
        Ok(())
    }

    pub fn get_readline_name() -> ::DynlibResult<Option<&'static str>> {
        match lib::rl_readline_name.map(|n| n.ptr()) {
            Ok(p) if p.is_null() || unsafe{*p}.ptr().is_null() => Ok(None),
            Ok(p) => Ok(unsafe{ CStr::from_ptr((*p).ptr()) }.to_str().ok()),
            Err(e) => Err(e)
        }
    }


    #[no_mangle]
    pub extern fn fake_completion_entry_function(_text: *const i8, _state: isize) -> *mut i8 {
        std::ptr::null_mut()
    }

    pub fn hijack_completion(ignore: isize, key: isize, new_function: lib::rl_completion_func_t) -> ::DynlibResult<isize> {
        // override both rl_attempted_completion_function AND rl_completion_entry_function
        // our magic happens in rl_attempted_completion_function
        // and we prevent the fallback from working in rl_completion_entry_function
        unsafe {
            let attempted_ptr = (*lib::rl_attempted_completion_function)?;
            original_rl_attempted_completion_function = *attempted_ptr.ptr();
            *attempted_ptr.ptr() = Some(new_function);

            let entry_ptr = (*lib::rl_completion_entry_function)?;
            original_rl_completion_entry_function = *entry_ptr.ptr();
            *entry_ptr.ptr() = Some(fake_completion_entry_function);

            let value = (*lib::rl_complete)?(ignore, key);

            *attempted_ptr.ptr() = original_rl_attempted_completion_function;
            *entry_ptr.ptr() = original_rl_completion_entry_function;

            Ok(value)
        }
    }

    pub fn vec_to_c_array(mut vec: Vec<String>) -> *const *const i8 {
        if vec.is_empty() {
            return std::ptr::null()
        }
        // make array of pointers
        let mut array: Vec<_> = vec.drain(..).map(|s| CString::new(s).unwrap().into_raw() as _).collect();
        array.push(std::ptr::null());
        Box::into_raw(array.into_boxed_slice()) as _
    }

    pub fn get_completions(text: *const i8, start: isize, end: isize) -> ::DynlibResult<*const *const i8> {
        unsafe {
            let matches = if let Some(func) = original_rl_attempted_completion_function {
                func(text, start, end)
            } else {
                std::ptr::null()
            };

            Ok(if matches.is_null() {
                let func = original_rl_completion_entry_function
                    .unwrap_or((*lib::rl_filename_completion_function)?);
                (*lib::rl_completion_matches)?(text, func)
            } else {
                matches
            })
        }
    }

    pub fn free_match_list(matches: *const *const i8) {
        for line in ::CArray(matches) {
            unsafe{ libc::free(line as _) };
        }
        unsafe{ libc::free(matches as _) };
    }

    pub fn ignore_completion_duplicates() -> ::DynlibResult<bool> {
        Ok(unsafe{ *(*lib::rl_ignore_completion_duplicates)?.ptr() > 0 })
    }

    pub fn filename_completion_desired() -> ::DynlibResult<bool> {
        Ok(unsafe{ *(*lib::rl_filename_completion_desired)?.ptr() > 0 })
    }

    pub fn mark_directories() -> ::DynlibResult<bool> {
        let value = unsafe{ (*lib::rl_variable_value)?(b"mark-directories\0".as_ptr() as _) };
        Ok(!value.is_null() && (unsafe{ CStr::from_ptr(value) }).to_bytes() == b"on")
    }

    pub fn tilde_expand(string: &str) -> ::DynlibResult<String> {
        let string = std::ffi::CString::new(string).unwrap();
        let string = unsafe{ (*lib::tilde_expand)?(string.as_ptr()) };
        let string = unsafe{ std::ffi::CString::from_raw(string) }.into_string();
        string.map_err(|_| "tilde_expand: invalid utf-8")
    }

    #[allow(non_upper_case_globals, non_camel_case_types)]
    mod lib {
        use std::marker::PhantomData;
        pub type rl_completion_func_t = extern fn(*const i8, isize, isize) -> *const *const i8;
        pub type rl_compentry_func_t = unsafe extern fn(*const i8, isize) -> *mut i8;

        #[derive(Copy, Clone)]
        pub struct Pointer<T>(usize, PhantomData<T>);
        impl<T> Pointer<T> {
            pub fn ptr(&self) -> *mut T { self.0 as *mut T }
        }

        macro_rules! readline_lookup {
            ($name:ident: $type:ty) => {
                readline_lookup!($name: $type; libc::RTLD_DEFAULT);
            };
            ($name:ident: $type:ty; $handle:expr) => {
                lazy_static! {
                    pub static ref $name: ::DynlibResult<$type> = unsafe {
                        dlsym!($handle, stringify!($name)).or_else(|_|
                            dynlib_call!(dlopen(b"libreadline.so\0".as_ptr() as _, libc::RTLD_NOLOAD | libc::RTLD_LAZY))
                            .and_then(|lib| dlsym!(lib, stringify!($name)))
                        )};
                }
            }
        }

        readline_lookup!(rl_refresh_line:                  unsafe extern fn(isize, isize) -> isize);
        readline_lookup!(rl_completion_matches:            unsafe extern fn(*const i8, rl_compentry_func_t) -> *const *const i8);
        readline_lookup!(rl_variable_value:                unsafe extern fn(*const i8) -> *const i8);
        readline_lookup!(rl_readline_name:                 Pointer<Pointer<i8>>);
        readline_lookup!(tilde_expand:                     unsafe extern fn(*const i8) -> *mut i8);
        readline_lookup!(rl_filename_completion_function:  rl_compentry_func_t);
        readline_lookup!(rl_completion_entry_function:     Pointer<Option<rl_compentry_func_t>>);
        readline_lookup!(rl_complete:                      unsafe extern fn(isize, isize) -> isize);
        readline_lookup!(rl_ignore_completion_duplicates:  Pointer<isize>);
        readline_lookup!(rl_filename_completion_desired:   Pointer<isize>);
        readline_lookup!(rl_attempted_completion_function: Pointer<Option<rl_completion_func_t>>);
    }
}

#[no_mangle]
pub extern fn rl_custom_function(ignore: isize, key: isize) -> isize {
    dump_error!(readline::hijack_completion(ignore, key, custom_complete), 0)
}

extern fn custom_complete(text: *const i8, start: isize, end: isize) -> *const *const i8 {
    let matches = dump_error!(readline::get_completions(text, start, end), std::ptr::null());
    let value = dump_error!(_custom_complete(text, matches), std::ptr::null());
    if let Some(value) = value {
        readline::free_match_list(matches);
        readline::vec_to_c_array(value)
    } else {
        matches as *const *const i8
    }
}

fn _custom_complete(text: *const i8, matches: *const *const i8) -> ::DynlibResult<Option<Vec<String>>> {
    let text = unsafe{ CStr::from_ptr(text as *const i8) }.to_bytes();
    let text = std::str::from_utf8(text).unwrap();

    let mut command = Command::new("rl_custom_complete");
    command.stdin(Stdio::piped()).stdout(Stdio::piped());
    command.arg(text);

    // pass the readline name to process
    if let Some(name) = readline::get_readline_name()? {
        command.env("READLINE_NAME", name);
    }

    let mut process = match command.spawn() {
        Ok(process) => process,
        // failed to run, do default completion
        Err(_) => { return Ok(None) },
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

    if readline::ignore_completion_duplicates()? {
        matches.sort();
        matches.dedup();
    }

    let append_slash = readline::filename_completion_desired()? && readline::mark_directories()?;

    for line in matches {
        // break on errors (but otherwise ignore)
        if stdin.write_all(line.as_bytes()).is_err() {
            break
        }

        if append_slash {
            let line = readline::tilde_expand(line)?;
            match std::fs::metadata(line) {
                Ok(ref f) if f.is_dir() => if stdin.write_all(b"/").is_err() {
                    break
                }
                _ => (),
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
        Err(_) => Ok(None),
        // exited with code != 0, leave line as is
        Ok(code) if ! code.success() => {
            readline::refresh_line()?;
            Ok(Some(vec![]))
        },
        Ok(_) => {
            readline::refresh_line()?;
            let stdout = process.stdout.unwrap();
            // readline multi completion doesn't play nice
            // join by spaces here and insert as one value instead
            let vec: Vec<_> = BufReader::new(stdout).lines().map(|l| l.unwrap()).collect();
            let mut string = vec.join(" ");
            if vec.len() > 1 {
                string.push(' ');
            }
            Ok(Some(vec![string]))
        }
    }
}
