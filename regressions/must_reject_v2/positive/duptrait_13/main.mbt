trait T13 { f(Self) -> Int }
struct S13 { x13 : Int }
impl T13 for S13 with f(self) { self.x13 }
impl T13 for S13 with f(self) { self.x13 }
fn main { println(S13::{x13:13}.f()) }
