///|
pub struct Handle {
  priv f : (Int32) -> Int32
}

///|
#export_name("f6min_next")
pub fn next(h : Handle) -> Unit {
  ignore(h)
}
