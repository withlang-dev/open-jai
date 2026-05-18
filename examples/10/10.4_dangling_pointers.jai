#import "Basic";

main :: () {
  a := New(int);
  print("%\n", a);    // address is non-deterministic
  print("%\n", << a); // => 0
  << a = 5;
  print("%\n", << a); // => 5

  free(a);
  print("%\n", << a); // => 5
  print("%\n", a);    // address is non-deterministic
  a = null;
  print("%\n", a);    // => null
}