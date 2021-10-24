ThatInput {
	classvar <>all; // a dictionary/cache to keep track of all instances which are unique identified by name

	var <>name; // unique identifier
	var <>input; // function or Ndef which provides an (audio) signal that shall be analyzed

	*initClass {
		all = ();
	}

	*new {|name, input|
		// check if the name is already used
		var res = all.at(name);
		if(res.isNil, {
			if(input.isNil, {
				Error("Unknown ThatInput - when creating a new ThatInput please also provide an input").throw;
			});
			res = super.new.init(name, input);
			all[name] = res;
		}, {
			// update input if we use an existing input
			res.input = input;
		});
		^res;
	}

	init { |name, input|
		this.name = name;
		this.input = input;
	}

	add { |...analyzers|
		analyzers.do({|analyzer|
			analyzer.setInput(this.input);
		});
	}

	clear {
		// we do not clear the analyzers here as those could already been
		// attached to another input which we currently do not keep track of
		all[this.name] = nil;
		// todo more gc?
	}
}


ThatAnalyzer {
	classvar <>all; // cache/dictionary for all existing instances

	var <>callback; // function that will get called with the results as first param
	var <>analyzer; // ugen that can perform identification
	var <>name; // is used for ndef and oscdef names - must be unique
	var <>input; // input that gets analyzed
	var <>oscChannelName; // the osc channel to send messages from server to sclang
	var <>allKeys;
	var <>identifier; // should this ever be different from name?
	// check...
	var <>numChannels;
	var <>ndef;
	var <>oscdef;

	var <>v;

	*initClass {
		all = ();
	}

	*new {|name, analyzer, callback|
		var res = all.at(name);
		if(res.isNil, {
			name.postln;
			if(analyzer.isNil, {
				Error("Please provide an analyzer").throw;
			});
			res = super.new.init(name, analyzer, callback);
			all[name] = res;
		}, {
			res.analyzer = analyzer;
			res.callback = callback;
		});
		^res;
	}

	init {|name, analyzer, callback|
		this.name = name;
		this.analyzer = analyzer;
		this.callback = callback;
		this.identifier = "that_%".format(this.name).asSymbol;
		this.oscChannelName = "/that/%".format(this.name);
	}

	clear {
		OSCdef(this.identifier).free;
		Ndef(this.identifier).clear;
		all[this.name] = nil;
	}

	setInput {|input|
		this.input = input;

		this.ndef = this.prCreateNdef();
		this.oscdef = this.prCreateOscDef();
	}

	prCreateNdef {
		Ndef(this.identifier, {
			var analysisChannels;
			var allChannels;
			var analysisResults;

			// allChannels = dim of event
			// does not work for ndefs?
			allChannels = this.input.value.asArray;
			this.numChannels = allChannels.size;

			analysisResults = allChannels.collect { |inChannel, i|
				// is .value(...) some multichannel stuff?
				this.analyzer.value(inChannel, allChannels, i);
			};

			allKeys = analysisResults.first.keys;
			allKeys.remove(\trig);
			allKeys = allKeys.asArray.sort;

			analysisResults.do { |event, i|
				var messageTrig = event[\trig];
				if(messageTrig.isNil) {
					Error("you should return an event with a 'trig' value from your analyzer").throw
				};

				// same as SendReply.kr/ar but rate can be adapted dynamically
				SendReply.perform(
					UGen.methodSelectorForRate(messageTrig.rate),
					messageTrig, // trig
					this.oscChannelName, // cmdName
					allKeys.collect { |key| event[key] }.flat, // values
					i // replyID
				);
			};
			SinOsc.kr(0.2);
		});
	}

	prCreateOscDef {
		OSCdef(this.identifier, { |msg|
			var values = msg[3..];
			var channelIndex = msg[2];
			var event = ();

			if(numChannels > 1) {
				event[\channelIndex] = channelIndex
			};
			// put the values back into the event, and unbubble singleton arrays like [100] –> 100
			if(allKeys.size==1, {
				// if only 1 value we return no dict but the value directly
				event = values[0].unbubble
			}, {
				allKeys.do { |key, i|
					event[key] = values[i].unbubble
				}
			});

			// store event also in object
			this.v = event;

			// callback time
			this.callback.value(event);

		}, this.oscChannelName).fix;
	}
}

ThatAmpAnalyzer : ThatAnalyzer {
	// todo make params editable
	*new{|name, callback, trigger=nil|
		var analyzer = {|in|
			var amp = Amplitude.kr(
				in: in,
				attackTime: \attackTime.kr(0.01),
				releaseTime: \releaseTime.kr(0.01),
			);

			(
				trig: if(trigger.isNil.not, {
					trigger;
				},{
					amp > \threshold.kr(0.05);
				}),
				amp: amp,
			);
		};
		// call new and init b/c otherwise init will not be called properly?
		^super.new(name, analyzer, callback).init(name, analyzer, callback);
	}
}

ThatFreqAnalyzer : ThatAnalyzer {
	*new{ |name, callback, trigger=nil|
		var analyzer = {|in|
			var freq;
			var hasFreq;
			var trig;

			#freq, hasFreq = Tartini.kr(
				in: in,
				threshold: \freqThreshold.kr(0.93)
			);

			trig = if(trigger.isNil.not, {
				trigger
			}, {
				Onsets.kr(
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
			});

			(trig: trig, freq: freq)
		};
		^super.new(name, analyzer, callback).init(name, analyzer, callback);
	}
}
