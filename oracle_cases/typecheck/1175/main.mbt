pub(all) enum Foo {
  Bar
  Baz(Int)
}

#proof_pure
pub fn Foo::rank(self : Foo) -> Int {
  match self {
    Bar => 0
    Baz(_) => 1
  }
}
