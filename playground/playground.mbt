///|
/// The playground: one call in, one JSON answer out.
///
/// Everything the library does to a source, done at once: the token stream,
/// the tree, the source rebuilt from the tree, the two rejections it can
/// make, and the run. A page that showed only the output would be hiding the
/// more interesting half -- a program that is refused still has a tree, and a
/// program that runs still has diagnostics to have not raised.
///
/// It is also a real embedder. The `host` module the guest can import is
/// supplied from here, and every part of the embedding surface is used: a
/// `write` that streams, an `argv`, a module of host functions, and a `call`
/// that answers them -- with a value, with one of the semantics' own
/// terminations, and with `Stuck` for what it cannot do.
///
/// A source may hold several modules, separated by a line that begins
/// `# module: NAME`. The first chunk is `__main__` unless it says otherwise,
/// which is what lets the page show imports at all.
pub fn analyze(source : String) -> String {
  let pieces = split_modules(source)
  let out = StringBuilder()
  out.write_string("{")
  out.write_string("\"modules\":[")
  for i, m in pieces {
    if i > 0 {
      out.write_string(",")
    }
    out.write_string("{\"name\":")
    out.write_string(json_string(m.0))
    out.write_string(",\"source\":")
    out.write_string(json_string(m.1))
    out.write_string("}")
  }
  out.write_string("]")

  // The entry module alone drives the token, tree and printer panes: those
  // are about ONE source, and showing three of each would say less.
  let entry = entry_source(pieces)
  out.write_string(",\"tokens\":")
  out.write_string(json_string(token_dump(entry)))
  let parsed = @purepy.parse(entry, name="__main__") catch {
    @err.PurePyError(d) => {
      out.write_string(",\"ast\":")
      out.write_string(json_string(""))
      out.write_string(",\"unparse\":")
      out.write_string(json_string(""))
      out.write_string(",\"check\":")
      out.write_string(verdict(Some(d), entry))
      out.write_string(",\"run\":")
      out.write_string(
        "{\"state\":\"not-run\",\"detail\":\"\",\"output\":\"\",\"log\":[]}",
      )
      out.write_string("}")
      return out.to_string()
    }
    e => {
      out.write_string(",\"ast\":\"\",\"unparse\":\"\",\"check\":")
      out.write_string(
        "{\"ok\":false,\"short\":" + json_string("\{e}") + ",\"report\":\"\"}",
      )
      out.write_string(
        ",\"run\":{\"state\":\"not-run\",\"detail\":\"\",\"output\":\"\",\"log\":[]}}",
      )
      return out.to_string()
    }
  }
  out.write_string(",\"ast\":")
  out.write_string(json_string(@ast.dump(parsed)))
  out.write_string(",\"unparse\":")
  out.write_string(json_string(@purepy.unparse(parsed)))

  // The whole program, checked and then run against the host below.
  let host_log : Array[String] = []
  let printed = StringBuilder()
  let host = playground_host(printed, host_log)
  let modules : Map[String, @ast.Module] = Map([])
  let mut broken : @err.Diagnostic? = None
  for m in pieces {
    try @purepy.parse(m.1, name=m.0) catch {
      @err.PurePyError(d) => broken = Some(d)
      _ => ()
    } noraise {
      tree => modules[m.0] = tree
    }
  }
  let tree = @purepy.source_tree(modules)
  let verdict_ = match broken {
    Some(d) => Some(d)
    None => @purepy.check_program(tree, host~)
  }
  out.write_string(",\"check\":")
  out.write_string(verdict(verdict_, entry))
  out.write_string(",\"run\":")
  match verdict_ {
    Some(_) =>
      out.write_string(
        "{\"state\":\"not-run\",\"detail\":\"the program was refused\",\"output\":\"\",\"log\":[]}",
      )
    None => {
      // A modest limit: a browser tab's stack is not a native thread's, and a
      // playground should report rather than take the page down with it.
      let result = @purepy.run_with(tree, host, max_depth=120)
      let (state, detail) = match result {
        Finished => ("finished", "")
        Terminated(SystemExit(n)) => ("exited", "status " + n.to_string())
        Terminated(k) => ("terminated", k.to_text())
        Undefined(why) => ("undefined", why)
        // The page's four host functions all answer on the spot, so this
        // never happens; the arm is here because a host is allowed to park.
        Suspended => ("undefined", "a host call that has not answered")
      }
      out.write_string("{\"state\":\"" + state + "\",\"detail\":")
      out.write_string(json_string(detail))
      out.write_string(",\"output\":")
      out.write_string(json_string(printed.to_string()))
      out.write_string(",\"log\":[")
      for i, line in host_log {
        if i > 0 {
          out.write_string(",")
        }
        out.write_string(json_string(line))
      }
      out.write_string("]}")
    }
  }
  out.write_string("}")
  out.to_string()
}

// ---------------------------------------------------------------------------
// The host
//
// Everything below is what an embedder writes. It is short on purpose: the
// surface is four things, and a page that shows a guest calling into its host
// needs all four.

///|
/// The module the guest may import, and what its functions do.
///
/// `now` returns a fixed instant rather than the real clock, so that a page
/// reloaded twice says the same thing; a host that wanted the real one would
/// read it here and nowhere else. `fail` exists to show a host answering with
/// one of the semantics' own terminations, and a call the host does not
/// recognise falls through to `Stuck`, which is how anything undefined is
/// reported whether the host or the language left it so.
fn playground_host(printed : StringBuilder, log : Array[String]) -> @eval.Host {
  let counters : Map[String, Int] = Map([])
  @eval.Host::new(
    write=fn(text) { printed.write_string(text) },
    argv=["playground.py", "--demo"],
    modules=[
      {
        name: "host",
        members: [
          ("VERSION", @value.Value::Str("playground 1")),
          ("log", @value.host_fn("host.log")),
          ("now", @value.host_fn("host.now")),
          ("count", @value.host_fn("host.count")),
          ("fail", @value.host_fn("host.fail")),
        ],
      },
    ],
    call=fn(name, args) {
      match (name, args) {
        // A value in, and the host's own side effect: the page shows this in
        // a pane of its own, so a reader can see the two sides apart.
        ("host.log", [v]) => {
          log.push(
            match v.str() {
              Some(t) => t
              None => "<" + v.kind_name() + ">"
            },
          )
          Val(None)
        }
        ("host.now", []) => Val(Int(1757260800N))
        // Host state the guest can reach only through this function.
        ("host.count", [Str(key)]) => {
          let n = match counters.get(key) {
            Some(n) => n + 1
            None => 1
          }
          counters[key] = n
          Val(Int(BigInt::from_int(n)))
        }
        // A host answering the way Python fails.
        ("host.fail", []) => Aborts(KeyError)
        _ =>
          Stuck(
            "'" +
            name +
            "' called with " +
            args.length().to_string() +
            " arguments of the wrong shape",
          )
      }
    },
  )
}

// ---------------------------------------------------------------------------
// Pieces

///|
/// Split a source into modules on `# module: NAME` lines.
fn split_modules(source : String) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  let mut name = "__main__"
  let body = StringBuilder()
  let mut any = false
  for line in source.split("\n") {
    let text = line.to_owned()
    match module_header(text) {
      Some(next) => {
        if any {
          out.push((name, body.to_string()))
        }
        name = next
        body.reset()
        any = true
      }
      None => {
        body.write_string(text)
        body.write_string("\n")
        any = true
      }
    }
  }
  if any {
    out.push((name, body.to_string()))
  }
  if out.is_empty() {
    out.push(("__main__", source))
  }
  out
}

///|
/// `# module: NAME`, with any amount of space around it.
fn module_header(line : String) -> String? {
  let trimmed = line.trim().to_owned()
  if !trimmed.has_prefix("#") {
    return None
  }
  let rest = trimmed[1:].to_owned().trim().to_owned()
  if !rest.has_prefix("module:") {
    return None
  }
  let name = rest[7:].to_owned().trim().to_owned()
  if name.is_empty() {
    None
  } else {
    Some(name)
  }
}

///|
fn entry_source(pieces : Array[(String, String)]) -> String {
  for p in pieces {
    if p.0 == "__main__" {
      return p.1
    }
  }
  pieces[0].1
}

///|
/// The token stream, in the format `pure-py tokens` prints.
fn token_dump(source : String) -> String {
  let src = @basic.Source::new(source, name="__main__")
  let out = StringBuilder()
  try @lexer.lex(src) catch {
    @err.PurePyError(d) => {
      out.write_string("!error ")
      out.write_string(d.short("__main__", source=src))
      out.write_string("\n")
    }
    e => out.write_string("!error \{e}\n")
  } noraise {
    tokens =>
      for t in tokens {
        out.write_string(t.span.to_display())
        out.write_string(" ")
        out.write_string(t.kind.name())
        out.write_string(" ")
        out.write_string(@basic.py_repr(t.text))
        out.write_string("\n")
      }
  }
  out.to_string()
}

///|
/// A rejection, rendered with the source around it, or `ok`.
fn verdict(d : @err.Diagnostic?, source : String) -> String {
  match d {
    None => "{\"ok\":true,\"short\":\"\",\"report\":\"\"}"
    Some(diag) => {
      let sources = @report.Sources::new()
      let id = sources.add("__main__", source)
      let config = {
        ..@render.default_config,
        format: Rich,
        color: Never,
        theme: @style.mono_theme,
      }
      let text = @render.render_string(
        diag.to_report(id),
        sources,
        config,
        is_tty=false,
      )
      "{\"ok\":false,\"short\":" +
      json_string(diag.message()) +
      ",\"report\":" +
      json_string(text) +
      "}"
    }
  }
}

///|
/// A JSON string literal. Small enough to write, and one dependency fewer.
fn json_string(s : String) -> String {
  let out = StringBuilder()
  out.write_char('"')
  for c in s {
    match c {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ =>
        if c.to_int() < 0x20 {
          out.write_string("\\u" + @basic.hex4(c.to_int()))
        } else {
          out.write_char(c)
        }
    }
  }
  out.write_char('"')
  out.to_string()
}
