# that

> This system is called "that", as in "you know that".

This is a condensed version of the real time sound analysis we did in the Musikinformatik seminar May/June 2021 @ RSH Düsseldorf which was rewritten into a Quark.

That allows to use values of UGens (which are running on the server) in the sclang domain which allows for interaction with live material by using analysis UGens on the signal.
This allows the creation of autonomous systems such as Voyager by George Lewis, but is not limited to that.

## Installation

You can use [Quarks](https://doc.sccode.org/Guides/UsingQuarks.html) to
install the extension.

```supercollider
Quarks.install("https://github.com/musikinformatik/that.git");
```

After installation please re-compile the Class Library (aka restart the
Interpreter) to make the class available in the interpreter.

## Documentation

To view the documentation search for the class *That* in
the Help Browser after installation and restart of the interpreter.

## Development

Everyone is invited to participate in development.
Please add and run tests if you modify the code.
Tests can be run via

```supercollider
TestThat.run();
```

## License

GPL 3
