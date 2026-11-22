trait T11 { f(Self) -> Int }
struct S11 { x11 : Int }
fn[A : T11] g(a : A) -> Int { a.f() }
fn main { println(g(S11::{x11:11})) }
