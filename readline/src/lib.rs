extern crate libc;

use std::io::{Write, BufReader, BufRead};
use std::process::{Command, Stdio};
use std::os::raw::c_char;
use std::ffi::CStr;

struct CArray {
    ptr: *const *const c_char
}

impl CArray {
    fn new(ptr: *const *const c_char) -> Self {
        CArray{ptr: ptr}
    }
}

impl Iterator for CArray {
    type Item = *const c_char;
    fn next(&mut self) -> Option<*const c_char> {
        if self.ptr.is_null() { return None }
        if unsafe{ *(self.ptr) }.is_null() { return None }
        let value = unsafe{ &**self.ptr };
        // let value = unsafe{ CStr::from_ptr(&**self.ptr) }.to_bytes();
        self.ptr = unsafe{ self.ptr.offset(1) };
        Some(value)
    }
}

fn make_cstr(ptr: *const c_char) -> &'static [u8] {
    unsafe{ CStr::from_ptr(ptr) }.to_bytes()
}

mod readline {
    use std::ffi::CStr;
    use std::os::raw::c_char;

    #[allow(non_camel_case_types)]
    type rl_completion_func_t = extern fn(*const u8, isize, isize) -> *const *const u8;
    #[allow(non_camel_case_types)]
    type rl_compentry_func_t = unsafe extern fn(*const u8, isize) -> *const u8;

    pub fn refresh_line() {
        unsafe{ rl_refresh_line(0, 0) };
    }

    pub fn get_readline_name() -> Option<&'static str> {
        if unsafe{ rl_readline_name }.is_null() { return None; }
        unsafe{ CStr::from_ptr(rl_readline_name) }.to_str().ok()
    }

    pub fn hijack_completion(ignore: isize, key: isize, new_function: rl_completion_func_t) -> isize {
        unsafe {
            original_rl_attempted_completion_function = rl_attempted_completion_function;
            rl_attempted_completion_function = Some(new_function);
            let value = rl_complete(ignore, key);
            rl_attempted_completion_function = original_rl_attempted_completion_function;
            value
        }
    }

    pub fn vec_to_c_array(mut vec: Vec<String>) -> *const *const u8 {
        if vec.is_empty() {
            return ::std::ptr::null();
        }
        // make array of pointers
        let mut array: Vec<*const u8> = vec.iter_mut().map(|s| {
            s.push('\0');
            s.as_ptr()
        }).collect();
        array.push(::std::ptr::null());
        array.shrink_to_fit();

        let ptr = array.as_ptr();

        // drop ref to data to avoid gc
        ::std::mem::forget(vec);
        ::std::mem::forget(array);
        return ptr;
    }

    #[allow(non_upper_case_globals)]
    static mut original_rl_attempted_completion_function: Option<rl_completion_func_t> = None;

    pub fn get_completions(text: *const u8, start: isize, end: isize) -> *const *const c_char {
        let matches = unsafe {
            let matches = if let Some(func) = original_rl_attempted_completion_function {
                func(text, start, end)
            } else {
                ::std::ptr::null()
            };

            if matches.is_null() {
                let func = match null_readline::rl_completion_entry_function {
                    Some(_) => rl_completion_entry_function,
                    None => rl_filename_completion_function,
                };
                rl_completion_matches(text, func)
            } else {
                matches
            }
        } as *const *const c_char;
        matches
    }

    pub fn free_match_list(matches: *const *const c_char) {
        for line in ::CArray::new(matches) {
            unsafe{ ::libc::free(line as *mut ::libc::c_void) };
        }
        unsafe{ ::libc::free(matches as *mut ::libc::c_void) };
    }

    #[link(name = "readline")]
    extern {
        fn rl_refresh_line(count: isize, key: isize) -> isize;
        fn rl_completion_matches(text: *const u8, func: rl_compentry_func_t) -> *const *const u8;
        static rl_readline_name: *const c_char;
        static mut rl_attempted_completion_function: Option<rl_completion_func_t>;

        fn rl_completion_entry_function(text: *const u8, state: isize) -> *const u8;
        fn rl_filename_completion_function(text: *const u8, state: isize) -> *const u8;

        fn rl_complete(ignore: isize, key: isize) -> isize;
    }

    // not sure why we need this
    mod null_readline {
        #[link(name = "readline")]
        extern {
            pub static rl_completion_entry_function: Option<super::rl_compentry_func_t>;
        }
    }
}

#[no_mangle]
pub extern fn rl_custom_function(ignore: isize, key: isize) -> isize {
    readline::hijack_completion(ignore, key, custom_complete)
}

extern fn custom_complete(text: *const u8, start: isize, end: isize) -> *const *const u8 {
    let matches = readline::get_completions(text, start, end);

    if let Some(value) = _custom_complete(text, matches) {
        readline::free_match_list(matches);
        readline::vec_to_c_array(value)
    } else {
        matches as *const *const u8
    }
}

fn _custom_complete(text: *const u8, matches: *const *const c_char) -> Option<Vec<String>> {
    let text = unsafe{ CStr::from_ptr(text as *const c_char) }.to_bytes();
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

    let matches: Vec<_> = CArray::new(matches).collect();
    let skip = if matches.len() == 1 { 0 } else { 1 };
    let matches = matches.into_iter().skip(skip);
    for line in matches {
        let line = make_cstr(line);
        if line.is_empty() { continue }
        // break on errors (but otherwise ignore)
        if ! (stdin.write_all(line).is_ok() && stdin.write_all(b"\n").is_ok() ) {
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
