

/*

       that
       ====

This system is called "that", as in "you know that".

     // ready to be used //

This is a condensed version of the real time sound analysis we did in the seminar May/June 2021
Useful functions are moved to a library which you can load, but also change.

The schema works similar to Ndef/Tdef. Using the same name twice overrides the old functions.
The name you choose (like \ampTrack) will be a name of the Ndef and an OSCdef


Note:
all functions have a namespace prefix "that", so you shouldn't get conflicts with other things
in your local environment.

If you want to integrate this into your own larger system, you can also load it into a separate environment, say q,
Then you can access the functions via q explicitly
q = ();
q.use { loadRelative("library/responsive-system-functions.scd") };
q.use { ~that_amplitudeDef(\ampTrack, { ... etc ... }) };


*/


// we need to find a good stereo sound file here.
// the file in the seminar I'm not sure what copyright it has.

(
// first, load the function library
loadRelative("library/that-system-functions.scd"); // you can look at theat file to see how to roll your own

// let's use an Ndef for input, so you can patch in something else:
Ndef(\input, { SoundIn.ar([0, 1]) });

// or alternatively, load a test buffer:


~path = // add your path
~that_buffer = Buffer.read(s, ~path);
)

(
Ndef(\input, { |rate = 1|
	PlayBuf.ar(
		numChannels: ~that_buffer.numChannels,
		bufnum: ~that_buffer,
		rate: BufRateScale.kr(~that_buffer) * rate.lag(1),
		loop: 1
	);
})
)


// ==================
// Amplitude Analysis
// ==================

// we will use amplitude analysis as a simple example to explain everything
// further down are examples for more complicated analysis forms.

// a very simple amplitude tracker (=> don't forget the dot after the function!)
~that_amplitudeDef.(\ampTrack, { Ndef.ar(\input).sum }, { |event| event.postln });

// the analysis happens in a new Ndef
Ndef(\ampTrack).pause;
Ndef(\ampTrack).resume;

// after you have stopped everything (e.g. by hitting cmd-period) you can wake it up again:
Ndef(\ampTrack).wakeUp;

// if you have a multichannel input, the messages have a "channelIndex" that tells you which
// of the channels has been triggered. Let's use both channels of the input now:
~that_amplitudeDef.(\ampTrack, { Ndef.ar(\input) }, { |event| event.postln });

// instead, you can also pass in a global trigger function, which triggers all channels together
// it also runs on the server
// then, the multichannel input will also be multichannel values:
~that_amplitudeDef.(\ampTrack, { Ndef.ar(\input) }, { |event| event.postln }, { Impulse.kr(2) });

// like this you can also make a "hand triggered" analysis:
~that_amplitudeDef.(\ampTrack, { Ndef.ar(\input) }, { |event| event.postln }, { \trig.tr });
Ndef(\ampTrack).set(\trig, 1); // each time you call this, the second function will receive an event

// let's take a look inside.
// ~that_amplitudeDef looks internally like this:
(
~that_amplitudeDef = { |name, inputFunction, responseFunction, triggerFunction|
	var analyser = { |input|
		var amp = Amplitude.kr(input, \attackTime.kr(0.01), \releaseTime.kr(0.01));
		var msgTrigger = amp > \threshold.kr(0.05);
		(trig: msgTrigger, amp: amp)
	};
	~that_analysisDef.(name, inputFunction, analyser, responseFunction, triggerFunction);
};
)

~that_amplitudeDef.(\ampTrack, { Ndef.ar(\input) }, { |event| event.postln });

// you can set these parameters, which will remain the same even if you redefine \ampTrack:
Ndef(\ampTrack).set(\attackTime, 0.3, \releaseTime, 0.6, \threshold, 0.1);

// tweak with GUI
NdefGui(Ndef(\ampTrack));

// free any def with that name and clear parameter settings
~that_freeDef.(\ampTrack);


// a longer example: feedback
(
// input through filter with amplitude threshold control
Ndef(\x, { |amp = 1, freq = 500|
	BPF.ar(Ndef.ar(\x, 2) + PinkNoise.ar(0.01), freq, 0.01, 10).tanh
}).play(vol:0.01);

~that_amplitudeDef.(\ampTrack,
	{ Ndef.ar(\input) },
	{ |event|
		var ampSum = event[\amp].asArray.sum;
		var outAmp = if(ampSum > 0.1) { 0 } { 1 };
		// each time also set a random frequency
		Ndef(\x).set(\freq, rrand(300.0, 800.0))
	},
	{ Impulse.kr(15) }
);
)

~that_freeDef.(\ampTrack);
Ndef(\x).clear;

// if you want to externally trigger the message, you can use the trigger variants. Here, you can pass a trigger.


// ==================
// Frequency Analysis
// ==================

// frequency analysis (uses Tartini)
~that_freqAnalyserDef.(\freqAnalysis, { Ndef.ar(\input).sum }, { |event| event.postln });

// use the function to set an Ndef
Ndef(\inputFreq, 440);
Ndef(\x, { SinOsc.ar(Ndef.kr(\inputFreq)) * 0.1 }).play;
~that_freqAnalyserDef.(\freqAnalysis, { Ndef.ar(\input) }, { |event| Ndef(\inputFreq, event[\freq]) });

// trigger only when needed.
~that_freqAnalyserDef.(\freqAnalysis, { Ndef.ar(\input) }, { |event| event.postln }, { \messageTrig.tr });
// Use the control messageTrig to trigger:
Ndef(\freqAnalysis).set(\messageTrig, 1);

// fetch a frequency from the input on the fly
(
Ndef(\x, { SinOsc.ar(Ndef.kr(\inputFreq)) * 0.1 }).play;
~that_freqAnalyserDef.(\freqAnalysis,
	{ Ndef.ar(\input) },
	{ |event| Ndef(\inputFreq, event[\freq].postln) },
	{ \messageTrig.tr }
)
);

Ndef(\input).play;
Ndef(\freqAnalysis).set(\messageTrig, 1);

// tweak with GUI
NdefGui(Ndef(\freqAnalysis));



~that_freeDef.(\freqAnalysis);

// ============================
// Frequency and Onset analysis
// ============================


// frequency and time onset (uses Tartini and Onsets Ugens)
~that_freqTimeAnalyserDef.(\freqTime, { Ndef.ar(\input) }, { |event| event.postln }, { Impulse.kr(2) });

// pause and resume
Ndef(\freqTime).pause;
Ndef(\freqTime).resume;

~that_freeDef.(\freqTime);


// =============
// MFCC analysis
// =============

~that_mfccAnalyserDef.(\freqMFCC, { Ndef.ar(\input) }, { |event| event.postln }, { Impulse.kr(2) });
~that_mfccAnalyserDef.(\freqMFCC, { Ndef.ar(\input).sum }, { |event| event.postln }); // doesn't work yet

~that_test.(\test, { Ndef.ar(\input) }, { |event| event.postln }, { Impulse.kr(2) });
~that_test.(\test, { Ndef.ar(\input) }, { |event| event.postln }); // doesn't work yet



// ==========================
// Collecting analysis events
// ==========================

(
var prevEvent;
// for collecting events, you need something to store them in, e.g. a List:
~that_memory = List.new;
~that_memorySize = 21;
// we write a little event collector
~that_addEventToMemory = { |event|
	if(prevEvent.notNil) {
		prevEvent[\dur] = event[\timePassed]; // add the time from last one to last one
		prevEvent[\timePassed] = nil; // no need for this.
		~that_memory.add(prevEvent);
		~that_memory = ~that_memory.keep(~that_memorySize.neg);
	};
	prevEvent = event;
};

// then you can add to it and make sure you keep only the last N (here N=21): events
~that_freqTimeAnalyserDef.(\freqTime,
	{ Ndef.ar(\input).sum }, // measure the sum of the input signal
	{ |event| ~that_addEventToMemory.(event) }, // fill the ~that_memory with events
);
)

Ndef(\input).play;
~that_memory

// what can we do with the ~that_memory?

// use one event directly, you should copy it before play
~that_memory[0].copy.play; // play first one
~that_memory.choose.copy.play; // play random one

// some operations:

~that_memory.collect { |x| x[\freq] }; // all frequency values
~that_memory.collect { |x| x[\dur] }; // all time values

// the simplest way to play it back:
Pseq(~that_memory).play;

// save a bit of memory:
~that_saved = ~that_memory.copy;
Pseq(~that_saved).play;
Pseq(~that_memory).play;

// make a memory space
~that_fondMemories = List.new;

// wait a little between each step
~that_fondMemories.add(~that_memory.copy);
~that_fondMemories.add(~that_memory.copy);
~that_fondMemories.add(~that_memory.copy);

// play back a random memory
Pseq(~that_fondMemories.choose).play;

// put them together in a series:
Pseq(~that_fondMemories.flatten(1)).play;


// ============================
// Transfroming analysis events
// ============================

// playing them back:
(
SynthDef(\sin, { |out, amp = 0.1, freq = 440, sustain = 1, pan = 2|
	var env;
	amp = AmpComp.kr(freq) * amp; // balance for loudness perception
	env = Env.linen(0.001, sustain * 0.4, sustain * 0.6, amp, \sin).ar(2) * (freq > 10); // limit max frequency
	Out.ar(out, Pan2.ar(SinOsc.ar(freq, 0.5pi) * env, pan))

}).add;
)

Ndef(\input).play;


(
Tdef(\x, {
	~that_memory.do { |event|
		event.postln;
		(
			instrument: \sin,
			freq: event[\freq] * [1, 5/4, 3/2] * 4, // a chord for each detected pitch
		).play;
		(event[\dur] * 4).wait; // 4 x slower
	}
}).play
)

// back to fond old memories
(
var mem = List.new;
5.do {
	var x = ~that_fondMemories.choose; // choose five random ones
	if(0.1.coin) { x = x.scramble }; // 10% chance: scramble time  order
	if(0.4.coin) { x = x.reverse }; // 40% chance: reverse time order
	if(0.3.coin) { x = x.collect { |e| e[\freq] * 1.5 } }; // 30% chance: transpose a fifth up
	mem.add(x)
};
mem.add(~that_memory); // end with current one
mem = mem.flatten(1);

Tdef(\x, {
	mem.do { |event|
		event.postln;
		(
			instrument: \sin,
			freq: event[\freq] * [1, 5/4, 3/2] * 2, // a chord for each detected pitch
			legato: 0.7
		).play;
		(event[\dur] * 2).wait; // 2 x slower
	}
}).play
)





// ============================
// Examples what to analyse
// Needs SC3-Plugins
// ============================


// which of the channels is louder right now?
// we need a global trigger function to have both channels' results at the same time
~that_amplitudeDef.(\ampTrack, { Ndef.ar(\input) }, { |event| event[\amp].postln.maxIndex.postln }, { Impulse.kr(8) });

// tempo tracker (needs several seconds to kick in, according to AutoTrack help file)
(
~that_tempoDef = { |name, inputFunction, responseFunction, triggerFunction|
	var analyser = { |input|
		var beat, half, quarter, tempo;
		var lock = \lock.kr(0); // fix it to the current one.
		#beat, half, quarter, tempo = AutoTrack.kr(input, lock);
		(trig: quarter, tempo: tempo)
	};
	~that_analysisDef.(name, inputFunction, analyser, responseFunction, triggerFunction);
};
)

~that_tempoDef.(\tempoTrack, { Ndef.ar(\input).sum }, { |event| event.postln });




// chromagram
// this one needs a triggerFunction
(
~that_chromaDef = { |name, inputFunction, responseFunction, triggerFunction|
	var analyser = { |input|
		var fftsize = 2048;
		var fft = FFT(LocalBuf(fftsize), input);
		var chroma = Chromagram.kr(fft, fftsize: fftsize, n: 12);
		(chroma: chroma)
	};
	~that_analysisDef.(name, inputFunction, analyser, responseFunction, triggerFunction);
};
)

~that_chromaDef.(\chromaTrack, { Ndef.ar(\input).sum }, { |event| event.postln }, { \messageTrig.tr });
Ndef(\chromaTrack).set(\messageTrig, 1);


// stereo version: two chromagrams
~that_chromaDef.(\chromaTrack, { Ndef.ar(\input) }, { |event| event.postln }, { \messageTrig.tr });
Ndef(\chromaTrack).set(\messageTrig, 1);


// example with a number of FFT analysis entries
(
~that_fftInfo = { |name, inputFunction, responseFunction, triggerFunction|
	var analyser = { |input|
		var fft, fftsize = 2048;
		var fftSlope, fftPeak, fftPower;
		fft = FFT(LocalBuf(fftsize), input);
		fftSlope = FFTSlope.kr(fft);
		fft = FFT(LocalBuf(fftsize), input);
		fftPeak = FFTPeak.kr(fft);
		fft = FFT(LocalBuf(fftsize), input);
		fftPower = FFTPower.kr(fft);

		(
			fftSlope: fftSlope,
			fftPeak: fftPeak,
			fftPower: fftPower
		)
	};
	~that_analysisDef.(name, inputFunction, analyser, responseFunction, triggerFunction);
};
)


~that_fftInfo.(\fftInfo, { Ndef.ar(\input).sum }, { |event| ~that_current = event.postln }, { \messageTrig.tr });
Ndef(\fftInfo).set(\messageTrig, 1);


~that_current[\fftSlope] // one float number
~that_current[\fftPower] // another number
~that_current[\fftPeak] // a pair of numbers, freq and magnitude of the maximum


// compare different frequency analysers
(
~that_compareFreqDef = { |name, inputFunction, responseFunction, triggerFunction|
	var analyser = { |input, allInputs|
		var zeroCrossing, pitch, tartini, fftPeak, panAnalysis;
		zeroCrossing = ZeroCrossing.ar(input);
		pitch = Pitch.kr(input, initFreq: 0, clar: 1);
		tartini = Tartini.kr(input);
		fftPeak = FFTPeak.kr(FFT(LocalBuf(2048), input));
		panAnalysis =
		(
			freqs: [zeroCrossing, pitch[0], tartini[0], fftPeak[0]],
			pitchClarity: pitch[1],
			tartiniClarity: tartini[1],
			fftPeakMagnitude: fftPeak[1]
		)
	};
	~that_analysisDef.(name, inputFunction, analyser, responseFunction, triggerFunction);
};
)

~that_compareFreqDef.(\fftInfo, { Ndef.ar(\input).sum }, { |event| ~that_current = event }, { \messageTrig.tr });
Ndef(\input).scope;

(
Ndef(\fftInfo).set(\messageTrig, 1);
~that_current[\freqs] // sometimes, different opinions ...
)

// ... use these different opinions for playing sounds

(
~that_compareFreqDef.(\fftInfo,
	{ Ndef.ar(\input).sum },
	{ |event|
		(instrument: \sin, freq: event[\freqs].postln, sustain: 0.4).play;
	},
	{ |inputs|
		Dust.kr(4)
	}
);
Ndef(\input).play(vol: 0.1);
)


// mind bender: multichannel expand (flop for right order)
(
~that_compareFreqDef.(\fftInfo,
	{ Ndef.ar(\input) },
	{ |event|
		(instrument: \sin, freq: event[\freqs].flop.postln, sustain: 0.4).play;
	},
	{ |inputs|
		Dust.kr(4)
	}
);
Ndef(\input).play(vol: 0.1);
)


// use trigger from audio
(
~that_compareFreqDef.(\fftInfo,
	{ Ndef.ar(\input).sum },
	{ |event|
		(instrument: \sin, freq: event[\freqs].postln * 2, sustain: 0.4).play;
	},
	{ |inputs|
		// trigger when threshold exceeded
		// this limits the max number of triggers
		// but keeps the reset random so that it avoids regular resets
		SetResetFF.kr(
			Amplitude.kr(inputs).sum > 0.05,
			Dust.kr(3)
		)
	}
);
Ndef(\input).play(vol: 0.5);
)



// delay the same thing
(
var waitTime = 5;
~that_compareFreqDef.(\fftInfo,
	{ Ndef.ar(\input).sum },
	{ |event|
		fork {
			waitTime.wait;
			waitTime = waitTime * rrand(0.9, 1.1);
			(
				instrument: \sin,
				freq: event[\freqs] * 2,
				sustain: 0.4,
				pan: 1.0.rand2
			).play;
		};
	},
	{ |inputs|
		// trigger when threshold exceeded
		// this limits the max number of triggers
		// but keeps the reset random so that it avoids regular resets
		SetResetFF.kr(
			Amplitude.kr(inputs).sum > 0.05,
			Dust.kr(3)
		)
	}
);
Ndef(\input).play(vol: 0.5);
)


// play a bit with the input
Ndef(\input).set(\rate, 0.8);
Ndef(\input).set(\rate, 1.25);
Ndef(\input).set(\rate, 1);
Ndef(\input).set(\rate, 1/2);



