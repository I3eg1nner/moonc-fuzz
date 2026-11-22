trait T22 { f(Self) -> Int }
struct S22 { x22 : Int }
impl T22 for S22 with f(self) { self.x22 }
impl T22 for S22 with f(self) { self.x22 }
fn main { println(S22::{x22:22}.f()) }
