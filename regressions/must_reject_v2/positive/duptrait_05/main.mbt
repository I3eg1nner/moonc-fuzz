trait T5 { f(Self) -> Int }
struct S5 { x5 : Int }
impl T5 for S5 with f(self) { self.x5 }
impl T5 for S5 with f(self) { self.x5 }
fn main { println(S5::{x5:5}.f()) }
