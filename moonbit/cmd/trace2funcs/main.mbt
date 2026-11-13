///|
/// Offline trace2funcs: read `nm -n` output + a QEMU `-d exec` log, emit the
/// same JSON shape as the Python harness.  Kept intentionally small so the
/// parity check can compare it byte-for-byte.
fn main {
  let args = @env.args()
  if args.length() < 3 {
    println("usage: trace2funcs <nm.txt> <exec.log> [out.json]")
    return
  }
  let nm_text = @fs.read_file_to_string(args[1]) catch {
    _ => {
      println("cannot read nm file")
      return
    }
  }
  let trace = @fs.read_file_to_string(args[2]) catch {
    _ => {
      println("cannot read trace")
      return
    }
  }
  let sym = @trace.SymTab::parse(nm_text)
  let summary = @trace.summarize_trace(trace, sym)
  let (lo, hi) = sym.text_range()
  let out = StringBuilder()
  out.write_string("{\"tool\":\"qemu-exec-trace+nm-moonbit\",")
  out.write_string("\"text_lo\":")
  out.write_string(lo.to_string())
  out.write_string(",\"text_hi\":")
  out.write_string(hi.to_string())
  out.write_string(",\"symbols\":")
  out.write_string(sym.len().to_string())
  out.write_string(",\"total_tb\":")
  out.write_string(summary.total_tb.to_string())
  out.write_string(",\"mapped_tb\":")
  out.write_string(summary.mapped_tb.to_string())
  out.write_string(",\"func_count\":")
  out.write_string(summary.funcs.length().to_string())
  out.write_string(",\"funcs\":")
  out.write_string(@trace.json_string_array(summary.funcs))
  out.write_string("}")
  let text = out.to_string()
  if args.length() >= 4 {
    @fs.write_string_to_file(args[3], text) catch {
      _ => println("cannot write output")
    }
  } else {
    println(text)
  }
}
