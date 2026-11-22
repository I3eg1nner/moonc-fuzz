enum E9 { A; B }
fn f(e : E9) -> Int { match e { A => 9 } }
fn main { println(f(A)) }
