// start a sound

(
Ndef(\thatSound, {
    SinOscFB.ar(
        freq: LinExp.kr(
            in: LFNoise2.kr([1.5, 0.7]),
            srclo: -1.0,
            dstlo: 200.0,
            dsthi: 1000.0,
        ),
        feedback: LFNoise0.kr(1.5)
    ) * EnvGen.kr(Env.perc, gate: Impulse.kr([1.2, 1.0])) * 0.2
}).play;
)

// we will use amplitude analysis as a simple example to explain everything
// further down are examples for more complicated analysis forms.
(
That.amp(
	name: \ampTest,
	input: { Ndef.ar(\thatSound) },
	callback: { |result| result.postln },
	triggerFunction: { Impulse.kr(10) }
);
)

// instead of a sound function, you can also pass in an Ndef directly.
(
That.amp(
	name: \ampTest,
	input: Ndef(\thatSound),
	callback: { |result| result.postln },
	triggerFunction: { Impulse.kr(10) }
);
)

// the analyzerFunction runs in a Ndef which is
// accessible by .analyzer
That(\ampTest).analyzer
// we can pause the execution of the analyzer
// by pausing this ndef
That(\ampTest).analyzer.pause
// and can also wake it up again
That(\ampTest).analyzer.resume;

// we can change the triggerFunction while it is running
// because the triggerFunction is attached to the analyzer
// we must use the constructor ".amp"
// which will build us a new analyzerFunction which respects
// the new trigger

// we will explicetely state the input as this allows for non-linear
// working through the examples
(
That.amp(
	name: \ampTest,
	input: Ndef(\thatSound),
	triggerFunction: { Impulse.kr(2) }
);
)

// We can also use the default trigger
// simply by omitting the triggerFunction
(
That.amp(
	name: \ampTest,
	input: Ndef(\thatSound),
);
)
// now we can tweak the parameters of this analyzer
// via the Ndef gui
That(\ampTest).analyzer.gui;

// We can also create a trigger which takes
// uses the default original trigger and
// modifies its behaviour
(
That.amp(
	name: \ampTest,
	input: Ndef(\thatSound),
	triggerFunction: {|in, defaultTrigger| defaultTrigger * Impulse.kr(5) },
);
)
// This now only updates if our defaultTrigger is active
// and is rate to 5 Hz limited by multiplying
// an impulse to it which acts as a boolean AND

// But note that the triggers must happen to coincide, which may be very rarely
// To limit the rate, normally we'd use Trig

(
That.amp(
	name: \ampTest,
	input: Ndef(\thatSound),
	triggerFunction: {|in, defaultTrigger| Trig.kr(defaultTrigger, 1/5) },
);
)



// We can also create a logical OR
// but for this we want another signal

(
Ndef(\thatSound, {
	SinOscFB.ar(
		LFNoise0.kr([1.0, 3.4]).exprange(100, 400),
		feedback: LFNoise0.kr([4, 7]).abs
	) * EnvGen.kr(Env.perc, gate: Impulse.kr([0.5, 0.15]))*0.2
}).play;
)

// note that our analyzer immediately picks up the
// changed signal

// now lets use an OR, at least an update at 5Hz
(
That.amp(
	name: \ampTest,
	input: Ndef(\thatSound),
	triggerFunction: {|in, defaultTrigger| defaultTrigger + Impulse.kr(5) }
);
)

// after we have finished our analysis we can
// clear our that instance just like a Ndef
That(\ampTest).clear;
Ndef(\thatSound).clear;




//////////////////////////
// Custom analyzerFunction

// Although there are a variety of analyzerFunctions provided via the
// constructors it is possible to write such a custom function.

(
Ndef(\thatSound, {
	SinOsc.ar(LFNoise0.kr(1.0).exprange(300, 800)) * 0.1
}).play
)

(
var f = { |in|
	// in is the input of the attached That instance
	(
		\amp: Amplitude.kr(in),
		\freq: Tartini.kr(in),
		// it is important to provide a trigger key which triggers
		// the sending of a OSC message from
		\trigger: Impulse.kr(1.0),
	)
};
That(
	name: \thatCustom,
	input: Ndef(\thatSound),
	analyzerFunction: f,
	callback: {|r| r.postln;}
);
)

// clear
That(\thatCustom).clear;
Ndef(\thatSound).clear;
::



// Feedback

// lets load and play a buffer
b = Buffer.read(s, Platform.resourceDir +/+ "sounds/a11wlk01.wav");
(
Ndef(\input, {|rate=1|
	PlayBuf.ar(b.numChannels, b, BufRateScale.kr(b) * rate.lag(1), loop: 1);
}).play(vol: 0.1);
)

// now create a synth which feedsback itself via a BPF
(
Ndef(\thatSound, { |amp = 1, freq = 500|
	BPF.ar(Ndef.ar(\thatSound, 1) + PinkNoise.ar(0.01), freq, 0.01, 10).tanh
}).play(vol: 0.01, out: 1);
)

// and now control the freq of the BPF via the input signal
(
That.freq(
	name: \inputFreq,
	input: Ndef(\input),
	callback: {|r| Ndef(\thatSound).set(\freq, r[0])}
)
)
::



// Markov Chain


(
// create an event in which we store our markov functions
q = q ? ();
// some parameters to tweak
q[\timeStep] = 0.05;
q[\timeMax] = 2.0;
q[\noteRange] = (0..88);

// init some private varibales
q[\lastMidiNote] = 0;
q[\currentTime] = 0;
q[\lastTime] = 0;
q[\lowInitValue] = 1e-5;

// helper function
q[\maxTimeStep] = (q[\timeMax]/q[\timeStep]).asInteger;
q[\timeMapper] = {|t| ((t/q[\timeStep]).roundUp).min(q[\maxTimeStep]-1)};
q[\timeMapperReverse] = {|s| s*q[\timeStep]};

// create 88x88 transition matrix for midi notes
// which is diagonal so we will create a chromatic glissando
// as an init distribution
q[\markovNote] = (q[\noteRange].size-1).collect({|i|
	(q[\noteRange].size-1).collect({|j|
		if((i+1)==j, {q[\lowInitValue]}, {0});
	})
});
// add 87->0
q[\markovNote][q[\noteRange].last-1][q[\noteRange].first] = q[\lowInitValue];

// create maxTimeStep x maxTimeStep transition matrix for
//time events which init is random
q[\markovTime] = (q[\maxTimeStep]).collect({
	(q[\maxTimeStep]).collect({
		// same init as notes
		q[\lowInitValue];
	})
});
)

(
// create some input signal - play is optional
Ndef(\guitar, {
	SoundIn.ar(0)
}).play;
)

(
// we use the results of our analyzers to modify the markov
// transition matrix to reflect our playing
That.freqTime(\thatGuitar,
	input: Ndef(\guitar),
	callback: { |r|
		var midiNote = r[\freq][0].cpsmidi.round;
		q[\currentTime] = q[\currentTime] + r[\timePassed][0];

		if(q[\lastMidiNote] != midiNote, {
			var time = q[\timeMapper].(q[\currentTime]);
			// increment markov matrix counter
			q[\markovNote][q[\lastMidiNote]][midiNote] = q[\markovNote][q[\lastMidiNote]][midiNote] + 1;
			q[\markovTime][q[\lastTime]][time] = q[\markovTime][q[\lastTime]][time] + 1;

			// re-adjust state
			q[\lastMidiNote] = midiNote;
			q[\lastTime] = time;
			q[\currentTime] = 0;

			["humanPlayer", time, midiNote].postln; // debug
		});
	},
);
)

(
// some synth to be played
SynthDef(\sinePerc, {|out|
	var sig = SinOscFB.ar(\freq.kr(200), \feedback.kr(1.0))*\amp.kr(0.5);
	var env = EnvGen.kr(Env.perc, doneAction: Done.freeSelf);
	sig = Pan2.ar(sig*env, 1.0); // map the output to the right channel
	Out.ar(out, sig);
}).add;

// play the synth according to the markov transition matrix
Tdef(\markovPlayer, {
	var curNote = q[\noteRange].choose;
	var curTime = 0;
	inf.do({
		// choose next event based on distribution of the markov transition matrix
		curNote = q[\noteRange].wchoose(q[\markovNote][curNote].normalizeSum);
		curTime = (0..q[\maxTimeStep]).wchoose(q[\markovTime][curTime].normalizeSum);
		(
			\instrument: \sinePerc,
			\freq: curNote.midicps,
		).play;
		["markovPlayer", curTime, curNote].postln; // debug
		q[\timeMapperReverse].(curTime).wait;
	});
}).play;
)

// stop and clean up
(
Tdef(\markovPlayer).clear;
Tdef(\guitar).clear;
That(\thatGuitar).clear;
q = nil;
)