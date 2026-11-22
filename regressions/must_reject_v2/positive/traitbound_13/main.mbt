trait T13 { f(Self) -> Int }
struct S13 { x13 : Int }
fn[A : T13] g(a : A) -> Int { a.f() }
fn main { println(g(S13::{x13:13})) }
