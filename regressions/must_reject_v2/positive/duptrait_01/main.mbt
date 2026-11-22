trait T1 { f(Self) -> Int }
struct S1 { x1 : Int }
impl T1 for S1 with f(self) { self.x1 }
impl T1 for S1 with f(self) { self.x1 }
fn main { println(S1::{x1:1}.f()) }
