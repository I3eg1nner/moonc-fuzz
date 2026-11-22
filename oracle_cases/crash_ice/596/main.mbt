pub struct T {
  val : @lib.Type
} derive(Default)

fn main {
  let _ = T::{val : None}
}
