{ stdenv
, cmake
}:

stdenv.mkDerivation {
  name = "bluespec-cmake";
  src = ./.;
  nativeBuildInputs = [ cmake ];
}
