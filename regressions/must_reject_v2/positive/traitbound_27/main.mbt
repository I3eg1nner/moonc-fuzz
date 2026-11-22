trait T27 { f(Self) -> Int }
struct S27 { x27 : Int }
fn[A : T27] g(a : A) -> Int { a.f() }
fn main { println(g(S27::{x27:27})) }
