trait T26 { f(Self) -> Int }
struct S26 { x26 : Int }
fn[A : T26] g(a : A) -> Int { a.f() }
fn main { println(g(S26::{x26:26})) }
