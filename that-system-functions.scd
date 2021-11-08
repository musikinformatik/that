
/*

that
====

This system is called "that", as in "you know that".


This first function allows us to construct analysis methods easily.

inputFunction:
-------------

a function that returns a UGen with audio input.
If it returns several channels, the analysis is done on each of them,
passing the results to the responseFunction as arrays

analysisFunction:
-----------------

a function that takes two arguments: mono audio input channel and the array of all channels
the function must return an event as follows:
(trig: trig, key1:val1, key2:val2, ...)

trig (message trigger) tells us when the responseFunction should be called.
It is a control rate or audio rate signal

responseFunction:
-----------------

a function that takes an event as argument with all the values from the keys above
The message trigger is not an analysis value.


triggerFunction:
----------------

this is optional, it should return a UGen. If it is given, it determines when the message is sent.
It is passed all channels as arguments, so that one can do an analysis on all of them together if
necessary. When a trigger function is given, the result values are multichannel event keys.

*/


// the main reason for complexity in this function is that
// if possible, we want to have values with keys and multichannel expansion, like (freq:[440, 550], amp:[0.1, 0.2])
// multichannel expansion is only reasonable if all channels are triggered by a single trigger
// this is why you need a triggerFunction for multichannel expansion

~that_analysisDef = { |uniqueName, inputFunction, analysisFunction, responseFunction, triggerFunction|
	var cmdName = '/analyser_' ++ uniqueName;
	var numChannels, allKeys, msgValueArray, multichannelExpandEach;

	multichannelExpandEach = triggerFunction.notNil; // only multichannel expand if there is a global trigger

	Ndef(uniqueName, {
		var analysisChannels, kr_or_ar, globalMessageTrig;
		var allChannels = inputFunction.value.asArray;
		var analysisResults;


		analysisResults = allChannels.collect { |inChannel, i|
			analysisFunction.value(inChannel, allChannels, i);
		};

		allKeys = analysisResults.first.keys;
		allKeys.remove(\trig);
		allKeys = allKeys.asArray.sort;

		if(multichannelExpandEach) {
			// e.g. [[freq1, freq2], [amp1, amp2], ...]
			msgValueArray = allKeys.collect { |key|
				analysisResults.collect { |event, i|
					event[key]
				}
			};
			globalMessageTrig = triggerFunction.(allChannels);
			kr_or_ar = UGen.methodSelectorForRate(globalMessageTrig.rate);
			SendReply.perform(kr_or_ar, globalMessageTrig, cmdName, msgValueArray.flat);
		} {
			analysisResults.do { |event, i|
				var messageTrig = event[\trig];
				var valuesInChannel = allKeys.collect { |key, i| event[key] };
				msgValueArray = valuesInChannel;
				if(messageTrig.isNil) {
					Error("you should return an event with a 'trig' value from your analysisFunction").throw
				};
				kr_or_ar = UGen.methodSelectorForRate(messageTrig.rate);
				SendReply.perform(kr_or_ar, messageTrig, cmdName, valuesInChannel.flat, i);
			}
		};
		numChannels = allChannels.size;
	});

	// receive OSC messages for the cmdName
	OSCdef(uniqueName, { |msg|
		var values = msg[3..];
		var channelIndex = msg[2];
		var event = ();

		if(multichannelExpandEach) {
			values = values.reshapeLike(msgValueArray)
		} {
			if(numChannels > 1) {
				event[\channelIndex] = channelIndex
			};
		};
		// put the values back into the event, and unbubble singleton arrays like [100] –> 100
		allKeys.do { |key, i| event[key] = values[i].unbubble };

		responseFunction.value(event)

	}, cmdName).fix;

	Ndef(uniqueName) // return the Ndef
};


// free all definitions of a given name

~that_freeDef = { |name|
	Ndef(name).clear;
	OSCdef(name).remove;
};



// Here come some simple definitions, you can just make your own

// naming convention: Def on the end to communicate that we can rewrite them on the fly
// TrigDef means that you pass a triggerFunction that will allow us to listen to a trigger control
// use Ndef(name).set(\messageTrig, 1) to trigger it


~that_amplitudeDef = { |name, inputFunction, responseFunction, triggerFunction|
	var analyser = { |input|
		var amp = Amplitude.kr(input, \attackTime.kr(0.01), \releaseTime.kr(0.01));
		var msgTrigger = amp > \threshold.kr(0.05);
		(trig: msgTrigger, amp: amp)
	};
	~that_analysisDef.(name, inputFunction, analyser, responseFunction, triggerFunction);
};


~that_freqAnalyserDef = { |name, inputFunction, responseFunction, triggerFunction|
	var analyser = { |input|
		var freq, hasFreq;
		var chain, msgTrigger, trig;

		#freq, hasFreq = Tartini.kr(input, \freqThreshold.kr(0.93));

		if(triggerFunction.isNil) {
			chain = FFT(LocalBuf(256), input);
			trig = Onsets.kr(chain,
				threshold: \threshold.kr(0.2),
				odftype: \wphase,
				relaxtime: \relaxtime.kr(0.02),
				floor: \floor.kr(0.01),
				mingap: \mingap.kr(12),
				medianspan: \medianspan.kr(11)
			) * (hasFreq > 0); // send only reliable values
		};
		(trig: trig, freq: freq)
	};

	~that_analysisDef.(name, inputFunction, analyser, responseFunction, triggerFunction)

};


~that_freqTimeAnalyserDef = { |name, inputFunction, responseFunction|
	var analyser = { |input|
		var freq, hasFreq;
		var trig, msgTrigger, chain, timePassed, amp;

		#freq, hasFreq = Tartini.kr(input, \freqThreshold.kr(0.93));
		amp = Amplitude.kr(input);


		chain = FFT(LocalBuf(256), input);
		trig = Onsets.kr(chain,
			threshold: \threshold.kr(0.2),
			odftype: \wphase,
			relaxtime: \relaxtime.kr(0.02),
			floor: \floor.kr(0.01),
			mingap: \mingap.kr(12),
			medianspan: \medianspan.kr(11)
		) * (hasFreq > 0); // send only reliable values

		timePassed = Timer.kr(trig);
		(trig: trig, freq: freq, timePassed: timePassed, amp: amp)
	};

	~that_analysisDef.(name, inputFunction, analyser, responseFunction)

};


~that_mfccAnalyserDef = { |name, inputFunction, responseFunction, triggerFunction, fftsize = 1024, numcoeff = 13|
	var analyser = { |input|
		var fft, spectrum;
		fft = FFT(LocalBuf(fftsize), input);
		spectrum = MFCC.kr(fft);
		(trig: fft, spectrum: spectrum)
	};
	~that_analysisDef.(name, inputFunction, analyser, responseFunction, triggerFunction)
};


~that_test = { |name, inputFunction, responseFunction, triggerFunction, fftsize = 1024, numcoeff = 13|
	var analyser = { |input|
		var array = DC.kr([1, 2, 3]);
		(trig: Impulse.kr(2), spectrum: array)
	};
	~that_analysisDef.(name, inputFunction, analyser, responseFunction, triggerFunction)
};









