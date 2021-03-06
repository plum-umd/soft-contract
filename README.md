This is the scaled up version of SCV,
intended to be (eventually) usable for real Racket programs.

[![Build Status](https://travis-ci.org/philnguyen/soft-contract.png?branch=master)](https://travis-ci.org/philnguyen/soft-contract)

Installation
=========================================

### Install Z3 and set `$Z3_LIB`:

Install [Z3](https://github.com/Z3Prover/z3), then set `$Z3_LIB` to the **directory**
containing:
  - `libz3.dll` if you're on Windows
  - `libz3.so` if you're on Linux
  - `libz3.dylib` if you're on Mac

### Install `soft-contract`

Clone the repository:

```
git clone git@github.com:philnguyen/soft-contract.git
```

Install:

```
cd soft-contract/soft-contract
raco pkg install
```

I will register this package on Racket Packages eventually.

Running
=========================================

Use `raco scv` to run the analysis on one example at `test/programs/safe/octy/ex-14.rkt`:
```
raco scv test/programs/safe/octy/ex-14.rkt
```

If the program is big and you want to print out something that looks like progress,
use `-p`:
```
raco scv -p test/programs/safe/games/snake.rkt
```

To verify multiple files that depend on one another,
pass them all as arguments.
If you forget to include any file that's part of the dependency,
it'll error out asking you to include the right one.
```
raco scv -p test/programs/safe/multiple/*.rkt
```


Generating benchmark results
=========================================

To generate benchmark results for (sub-)test-suites, use `test/gen-table.rkt`.
The outputs are in a form that can be conveniently copied to a latex document as a table.

For example, to run the occurence benchmarks, execute:

```
racket test/gen-table.rkt test/programs/safe/octy
```
