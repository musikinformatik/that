That {
	classvar <all; // cache/dictionary for all existing instances

	var <name; // is also used to generate Ndef and OSCdef names - must be unique!
	var <input; // input that gets analyzed
	var <analyzerFunction; // function which analyzes the input and returns an event
	var <>callback; // function that will get called with the results as first param

	// public variables
	var <latestValue; // last stored value/event that was sent from analyzer
	var <analyzer; // a node proxy which runs the analyser and can be acessed to modify arguments

	// private variables
	var analyzerResultKeys; // keys of the event that the analyzer returns
	var defName; // name used for OSCdef and Ndef keys
	var oscChannelName; // osc channel name to send messages from server to sclang
	var numInputChannels; // needed for unwrapping multichannel results
	var oscFunc; // responds to messages from analyzer

	*initClass {
		all = ();
	}

	*new {|name, input, analyzerFunction, callback|
		var res = all.at(name);
		if(res.isNil, {
			if(analyzerFunction.isNil, {
				Error("Please provide an analyzerFunction").throw;
			});
			callback = callback ? {}; // enforce a function as callback and not allow nil
			res = super.newCopyArgs(name, input, analyzerFunction, callback).init.();
			all[name] = res;
		}, {
			input !? { res.input = input };
			analyzerFunction !? { res.analyzerFunction = analyzerFunction };
			callback !? { res.callback = callback };
		});
		^res
	}

	init {
		defName = "that_%".format(name).asSymbol;
		oscChannelName = "/that/%".format(name);
		this.input = input;
	}

	clear {
		oscFunc.free;
		Ndef(defName).clear;
		all[name] = nil;
	}

	input_ {|newInput|
		input = newInput;
		this.prUpdateDefs();
	}

	analyzerFunction_ {|newAnalyzerFunction|
		analyzerFunction = newAnalyzerFunction;
		this.prUpdateDefs();
	}

	prUpdateDefs {
		this.prCreateNdef();
		this.prCreateOscFunc();
	}

	prCreateNdef {
		analyzer = Ndef(defName, {
			var inputChannels;
			var analyzerResults;
			var oscPayload;
			var summedTriggers;

			inputChannels = input.value.asArray;
			numInputChannels = inputChannels.size;

			analyzerResults = inputChannels.collect { |inputChannel, i|
				// .value is a call on a function that returns an event with signal graphs
				// of UGens. If it specifies the arguments (which is optional),
				// it can make the resulting signal graphs depend on them or add extra
				// information to the event. E.g. besides each channel, it can access
				// all other input channels and the index of the current
				// channel (in a multichannel analysis signal).
				analyzerFunction.value(inputChannel, inputChannels, i);
			};

			//  prepare payload
			analyzerResultKeys = analyzerResults.first.keys.remove(\trigger).asArray.sort;
			// convert to [foo_ch1, foo_ch2, bar_ch1, bar_ch2]
			oscPayload = analyzerResultKeys.collect({ |key|
				analyzerResults.collect({ |event|
					event[key];
				});
			});

			if(analyzerResults.first[\trigger].isNil, {
				Error("the analyzerFunction must return an event with a 'trigger' key/value").throw
			});

			// sum up all active triggers to perform an OR operation
			summedTriggers = analyzerResults.collect({|r| r[\trigger]}).sum;

			// same as SendReply.kr/ar but rate can be adapted dynamically
			SendReply.perform(
				UGen.methodSelectorForRate(summedTriggers.rate),
				summedTriggers, // trig
				oscChannelName, // cmdName
				oscPayload.flat, // values we evaluated from the analyzer, index 3.. of the OSC message
				-1, // implicitly set replyID to -1, index 2 of the OSC message
			);
		});
	}

	prCreateOscFunc {
		oscFunc = OSCFunc({ |msg|
			var values = msg[3..];
			var event = ();
			// msg[2] is replyID of SendReply which we set fixed to -1

			if(analyzerResultKeys.size==1, {
				// if only one key exists in we return an array and not a dict
				event = values
			}, {
				// else we need to unwrap the keys according in respect to the channels
				analyzerResultKeys.do { |key, i|
					// the incoming message looks like [foo_ch1, foo_ch2, bar_ch1, bar_ch2]
					// and gets transformed to (foo: [foo_ch1, foo_ch2], bar: [bar_ch1, bar_ch2])
					var arrayOffset = i*numInputChannels;
					event[key] = values[arrayOffset..(arrayOffset+numInputChannels-1)]
				}
			});

			// store event also in object
			latestValue = event;

			// callback time
			callback.value(event);

		}, oscChannelName).fix;
	}

	*prCreateTrigger {|in, defaultTrigger, triggerFunction|
		^if(triggerFunction.isNil, {
			defaultTrigger
		}, {
			triggerFunction.(in, defaultTrigger)
		});
	}

	*amp {|name, input, callback, triggerFunction|
		var analyzerFunction = {|in|
			var amp = Amplitude.kr(
				in: in,
				attackTime: \attackTime.kr(0.01),
				releaseTime: \releaseTime.kr(0.01),
			);

			(
				trigger: this.prCreateTrigger(in, amp > \threshold.kr(0.05), triggerFunction),
				amp: amp,
			);
		};
		^this.new(name, input, analyzerFunction, callback)
	}

	*freq {|name, input, callback, triggerFunction|
		var analyzerFunction = {|in|
			var freq;
			var hasFreq;
			var defaultTrigger;

			#freq, hasFreq = Tartini.kr(
				in: in,
				threshold: \freqThreshold.kr(0.93)
			);

			defaultTrigger = Onsets.kr(
				chain: FFT(
					buffer: LocalBuf(256),
					in: in
				),
				threshold: \threshold.kr(0.2),
				odftype: \wphase,
				relaxtime: \relaxtime.kr(0.02),
				floor: \floor.kr(0.01),
				mingap: \mingap.kr(12),
				medianspan: \medianspan.kr(11)
			) * (hasFreq > 0); // send only reliable values

			(
				trigger: this.prCreateTrigger(in, defaultTrigger, triggerFunction),
				freq: freq

			)
		};
		^this.new(name, input, analyzerFunction, callback)
	}

	*freqTime {|name, input, callback, triggerFunction|
		var analyzerFunction = { |in|
			var freq;
			var hasFreq;
			var defaultTrigger;
			var trigger;

			#freq, hasFreq = Tartini.kr(
				in: in,
				threshold: \freqThreshold.kr(0.93)
			);

			defaultTrigger = Onsets.kr(
				chain: FFT(LocalBuf(256), in),
				threshold: \threshold.kr(0.2),
				odftype: \wphase,
				relaxtime: \relaxtime.kr(0.02),
				floor: \floor.kr(0.01),
				mingap: \mingap.kr(12),
				medianspan: \medianspan.kr(11)
			) * (hasFreq > 0); // send only reliable values

			trigger = this.prCreateTrigger(in, defaultTrigger, triggerFunction);

			(
				trigger: trigger,
				freq: freq,
				timePassed: Timer.kr(trigger),
				amp:  Amplitude.kr(input),
			)
		};
		^this.new(name, input, analyzerFunction, callback)
	}

	*identity {|name, input, callback, triggerFunction|
		var analyzerFunction = {|in|
			(
				trigger: this.prCreateTrigger(in, Impulse.kr(1.0), triggerFunction),
				identity: in,
			)
		};
		^this.new(name, input, analyzerFunction, callback)
	}

	*mfcc {|name, input, callback, triggerFunction, fftSize=1024|
		var analyzerFunction = {|in|
			var fft;
			var spectrum;

			fft = FFT(LocalBuf(fftSize), input);
			spectrum = MFCC.kr(fft);
			(
				trigger: this.prCreateTrigger(in, fft, triggerFunction),
				spectrum: spectrum,
			)
		};
		^this.new(name, input, analyzerFunction, callback)
	}
}
