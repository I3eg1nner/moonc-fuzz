typealias S[T] = Array[T]

enum Nested[Z] {
  Cons(Z,Nested[S[Z]])
  Epsilon
}

fn Nested::length[A](self : Nested[A]) -> Int {
  match self {
    Cons(_,xs) => 1 + Nested::length(xs)
    Epsilon => 0
  }
}
