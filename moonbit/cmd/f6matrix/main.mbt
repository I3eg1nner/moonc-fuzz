///|
/// F6 boundary matrix: which exported shapes make the native backend reject a
/// closure-containing type?  Every case is a self-contained foreign_library
/// package; the control cases must build with rc=0.
///
/// This also serves as the "native export/link" surface from the review: it
/// turns one ICE into a trigger map instead of another duplicate campaign.
struct Variant {
  name : String
  body : String
}

///|
fn join(a : String, b : String) -> String {
  if a.has_suffix("/") {
    a + b
  } else {
    a + "/" + b
  }
}

///|
fn rm_rf(path : String) -> Unit {
  if !@fs.path_exists(path) {
    return
  }
  let isdir = @fs.is_dir(path) catch { _ => false }
  if isdir {
    let names = @fs.read_dir(path) catch { _ => [] }
    for n in names {
      rm_rf(join(path, n))
    }
    @fs.remove_dir(path) catch {
      _ => ()
    }
  } else {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
}

///|
async fn run_variant(root : String, v : Variant) -> String {
  let d = join(root, v.name)
  rm_rf(d)
  @corpus.ensure_dir(d)
  let mod = "name = \"f6" + v.name + "\"\nversion = \"0.1.0\"\n"
  @fs.write_string_to_file(join(d, "moon.mod"), mod) catch {
    _ => ()
  }
  @fs.write_string_to_file(
    join(d, "moon.pkg"),
    "pkgtype(kind: \"foreign_library\")\n",
  ) catch {
    _ => ()
  }
  @fs.write_string_to_file(join(d, "main.mbt"), v.body) catch {
    _ => ()
  }
  let r = @exec.run(
    "/home/user/.moon/bin/moon",
    ["build", "--target", "native"],
    d,
    120000,
  )
  let blob = r.stderr + r.stdout
  let kind = @exec.classify(r)
  let detail = @exec.ice_detail(r)
  let mut sig = ""
  if blob.contains("reject_export_type_containing_unsupported_callback") {
    sig = "closure_export_rejected"
  } else if kind == "OK" {
    sig = "built"
  }
  "{\"variant\":\"" +
  v.name +
  "\",\"rc\":" +
  r.rc.to_string() +
  ",\"kind\":\"" +
  kind +
  "\",\"sig\":\"" +
  sig +
  "\",\"detail\":\"" +
  @corpus.json_escape(detail) +
  "\"}"
}

///|
async fn main {
  let root = "/tmp/mbtfuzz_f6matrix"
  rm_rf(root)
  @corpus.ensure_dir(root)
  let variants : Array[Variant] = [
    {
      name: "priv_closure",
      body: "pub struct H { priv f : (Int32) -> Int32 }\n#export_name(\"n\")\npub fn n(h : H) -> Unit { ignore(h) }\n",
    },
    {
      name: "pub_closure",
      body: "pub struct H { f : (Int32) -> Int32 }\n#export_name(\"n\")\npub fn n(h : H) -> Unit { ignore(h) }\n",
    },
    {
      name: "array_closure",
      body: "pub struct H { priv fs : Array[(Int32) -> Int32] }\n#export_name(\"n\")\npub fn n(h : H) -> Unit { ignore(h) }\n",
    },
    {
      name: "option_closure",
      body: "pub struct H { priv f : ((Int32) -> Int32)? }\n#export_name(\"n\")\npub fn n(h : H) -> Unit { ignore(h) }\n",
    },
    {
      name: "alias_closure",
      body: "type Cb = (Int32) -> Int32\npub struct H { priv f : Cb }\n#export_name(\"n\")\npub fn n(h : H) -> Unit { ignore(h) }\n",
    },
    {
      name: "enum_closure",
      body: "pub enum E { C((Int32) -> Int32) }\npub struct H { priv e : E }\n#export_name(\"n\")\npub fn n(h : H) -> Unit { ignore(h) }\n",
    },
    {
      name: "generic_closure",
      body: "pub struct Box[T] { priv v : T }\npub struct H { priv b : Box[(Int32) -> Int32] }\n#export_name(\"n\")\npub fn n(h : H) -> Unit { ignore(h) }\n",
    },
    {
      name: "nested_closure",
      body: "pub struct Inner { priv f : (Int32) -> Int32 }\npub struct H { priv i : Inner }\n#export_name(\"n\")\npub fn n(h : H) -> Unit { ignore(h) }\n",
    },
    {
      name: "control_no_export",
      body: "pub struct H { priv f : (Int32) -> Int32 }\npub fn n(h : H) -> Unit { ignore(h) }\n",
    },
    {
      name: "control_no_closure",
      body: "pub struct H { priv x : Int32 }\n#export_name(\"n\")\npub fn n(h : H) -> Unit { ignore(h) }\n",
    },
  ]
  for v in variants {
    println(run_variant(root, v))
  }
}
