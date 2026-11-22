fn mk(n : Int) -> UInt? {
  if n > 100 { None } else { Some(0x80000000U | n.reinterpret_as_uint()) }
}
fn main {
  match mk(1) {
    Some(x) => {
      println(x.to_uint64().to_string(radix=16))
      println(x.to_double().to_string())
      println((x >> 1).to_string(radix=16))
    }
    None => ()
  }
}
