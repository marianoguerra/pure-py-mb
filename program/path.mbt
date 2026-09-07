///|
/// Just enough of Python's `pathlib` to print the same paths the reference
/// prints.
///
/// The messages of `check_program.py` contain paths built with `pathlib`, and
/// `pathlib` normalises in ways a naive join does not: the parent of `main.py`
/// is `.`, and joining `.` with `helper.py` gives `helper.py` and not
/// `./helper.py`. Those two show up verbatim in `module 'helper' not found
/// under .` and in `helper.py: duplicate name 'f' in mutual region`.
pub fn parent(p : String) -> String {
  match p.rev_split_once("/") {
    Some((head, _)) => if head.is_empty() { "/" } else { head.to_owned() }
    None => "."
  }
}

///|
/// `pathlib`'s `/`: a lone `.` on the left disappears.
pub fn join(base : String, child : String) -> String {
  if base == "." {
    child
  } else if base.has_suffix("/") {
    base + child
  } else {
    base + "/" + child
  }
}

///|
/// The file name, without its directories.
pub fn name_of(p : String) -> String {
  match p.rev_split_once("/") {
    Some((_, tail)) => tail.to_owned()
    None => p
  }
}

///|
/// The file name without its last extension.
pub fn stem(p : String) -> String {
  let base = name_of(p)
  match base.rev_split_once(".") {
    Some((head, _)) => head.to_owned()
    None => base
  }
}

///|
/// `a.b.c` has proper prefixes `a` and `a.b`.
pub fn proper_prefixes(q : String) -> Array[String] {
  let parts = q.split(".").map(fn(v) { v.to_owned() }).collect()
  let out : Array[String] = []
  for i in 1..<parts.length() {
    out.push(parts[:i].to_owned().join("."))
  }
  out
}

///|
/// Every name and all of its proper prefixes, sorted and without repeats.
pub fn with_proper_prefixes(names : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for n in names {
    for q in proper_prefixes(n) {
      if !out.contains(q) {
        out.push(q)
      }
    }
    if !out.contains(n) {
      out.push(n)
    }
  }
  @basic.sort_names(out)
  out
}
