+ UGen {
	that { | callback, trigger |
		var id = UniqueID.next;

		callback = callback ? {};
		trigger = trigger ? Impulse.kr(10.0);

		// register id:callback and SynthDef:id
		That.ugenCallbacks[id] = callback;
		That.ugenMap[UGen.buildSynthDef.name.asSymbol] = id;

		SendReply.perform(
			UGen.methodSelectorForRate(trigger.rate),
			trigger, // trig
			That.ugenOscAddress, // cmdName
			this, // values
			id // sendReply
		);
	}
}
