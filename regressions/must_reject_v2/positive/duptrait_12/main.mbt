trait T12 { f(Self) -> Int }
struct S12 { x12 : Int }
impl T12 for S12 with f(self) { self.x12 }
impl T12 for S12 with f(self) { self.x12 }
fn main { println(S12::{x12:12}.f()) }
