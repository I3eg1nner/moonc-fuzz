trait T24 { f(Self) -> Int }
struct S24 { x24 : Int }
impl T24 for S24 with f(self) { self.x24 }
impl T24 for S24 with f(self) { self.x24 }
fn main { println(S24::{x24:24}.f()) }
