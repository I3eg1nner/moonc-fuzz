///|
fn read_set(path : String) -> Array[String] {
  let text = @fs.read_file_to_string(path) catch {
    _ => {
      println("cannot read \{path}")
      return []
    }
  }
  let fs = @covlib.parse_json(text) catch {
    _ => {
      println("bad JSON: \{path}")
      return []
    }
  }
  fs.sorted()
}

///|
fn main {
  let args = @env.args()
  if args.length() < 2 {
    println("usage: cov <union|diff|report|minimize> [files...]")
    return
  }
  let cmd = args[1]
  let files = args[2:]
  if cmd == "union" {
    let sets : Array[Array[String]] = []
    for p in files {
      sets.push(read_set(p))
    }
    println(@covlib.union_stats(sets))
  } else if cmd == "diff" {
    if files.length() < 2 {
      println("usage: cov diff A.json B.json")
      return
    }
    let a = read_set(files[0])
    let b = read_set(files[1])
    let sa = @covlib.FuncSet::new(a)
    let sb = @covlib.FuncSet::new(b)
    println("baseline=\{sa.len()} current=\{sb.len()}")
    println(
      "added=\{sb.difference(sa).len()} removed=\{sa.difference(sb).len()}",
    )
  } else if cmd == "report" {
    println(@covlib.report_header())
    for p in files {
      let s = read_set(p)
      let n = s.length()
      println(@covlib.report_row(p, n, 0, s.length(), []))
    }
  } else if cmd == "minimize" {
    let sets : Array[Array[String]] = []
    for p in files {
      sets.push(read_set(p))
    }
    let chosen = @covlib.minimize_sets(sets)
    println("chosen=\{chosen.length()} of \{sets.length()}")
    for i in chosen {
      println(files[i])
    }
  } else {
    println("unknown command: \{cmd}")
  }
}
