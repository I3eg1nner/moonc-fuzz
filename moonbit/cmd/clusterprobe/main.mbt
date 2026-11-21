// Usage: clusterprobe fmt FILE...
//
// Runs `moonfmt FILE -o <tmp>` for each file and prints the formatter cluster
// signature.  Used by the acceptance control to show that two different
// sources with the same formatter error share a signature, while a different
// error does not.

///|
async fn main {
  let args = @env.args()
  if args.length() < 3 || args[1] != "fmt" {
    println("usage: clusterprobe fmt FILE...")
    return
  }
  let moonfmt = @stager.tool_path("moonfmt")
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "/tmp"
  }
  for i in 2..<args.length() {
    let raw = args[i]
    let f = if raw.has_prefix("/") { raw } else { @stager.join(cwd, raw) }
    let out = "/tmp/clusterprobe_" +
      @env.now().to_string() +
      "_" +
      i.to_string() +
      ".mbt"
    let r = @exec.run(moonfmt, [f, "-o", out], "/tmp", 20000)
    let sig = @cluster.formatter_signature(r.rc, r.stderr, r.stdout)
    println(
      "{\"file\":\"" +
      @stager.escape(f) +
      "\",\"sig\":\"" +
      @stager.escape(sig) +
      "\"}",
    )
    ignore(@fs.remove_file(out) catch { _ => () })
  }
}
