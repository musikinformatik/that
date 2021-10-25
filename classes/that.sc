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
	var oscdef; // responds to messages from analyzer

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
		^res;
	}

	init {
		defName = "that_%".format(name).asSymbol;
		oscChannelName = "/that/%".format(name);
		this.input = input;
	}

	clear {
		OSCdef(defName).free;
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
		this.prCreateOscDef();
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
				// is .value(...) some multichannel stuff?
				analyzerFunction.value(inputChannel, inputChannels, i);
			};

			//  prepare payload
			analyzerResultKeys = analyzerResults.first.keys.remove(\trig).asArray.sort;
			// convert to [foo_ch1, foo_ch2, bar_ch1, bar_ch2]
			oscPayload = analyzerResultKeys.collect({ |key|
				analyzerResults.collect({ |event|
					event[key];
				});
			});

			if(analyzerResults.first[\trig].isNil, {
				Error("you should return an event with a 'trig' value from your analyzerFunction").throw
			});

			// sum up all active triggers to perform an OR operation
			summedTriggers = analyzerResults.collect({|r| r[\trig]}).sum;

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

	prCreateOscDef {
		oscdef = OSCdef(defName, { |msg|
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

	*amp {|name, input, callback, trigger|
			var analyzerFunction = {|in|
			var amp;
			var defaultTrig;

			amp = Amplitude.kr(
				in: in,
				attackTime: \attackTime.kr(0.01),
				releaseTime: \releaseTime.kr(0.01),
			);

			defaultTrig = amp > \threshold.kr(0.05);

			(
				trig: if(trigger.isNil, {
					defaultTrig;
				}, {
					trigger.(in, defaultTrig);
				}),
				amp: amp,
			);
		};
		^this.new(name, input, analyzerFunction, callback);
	}

	*freq {|name, input, callback, trigger|
		var analyzerFunction = {|in|
			var freq;
			var hasFreq;
			var defaultTrig;

			#freq, hasFreq = Tartini.kr(
				in: in,
				threshold: \freqThreshold.kr(0.93)
			);

			defaultTrig = Onsets.kr(
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
				trig: if(trigger.isNil, {
					defaultTrig;
				}, {
					trigger.(in, defaultTrig);
				}),
				freq: freq

			)
		};
		^this.new(name, input, analyzerFunction, callback);
	}
}
