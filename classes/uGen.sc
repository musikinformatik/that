+ UGen {
	that { | callback, trigger |
		var oscAddress = "/that/ugen/%/%".format(synthDef, synthIndex);
		oscAddress.postln;
		callback = callback ? {};
		trigger = trigger ? Impulse.kr(10.0);
		SendReply.perform(
			UGen.methodSelectorForRate(trigger.rate),
			trigger, // trig
			oscAddress, // cmdName
			this, // values
		);

		OSCdef(key: oscAddress, func:  { |msg|
			var nodeId, replyId, values;
			#nodeId, replyId ... values = msg[1..];
			callback.(values, nodeId);
		}, path: oscAddress).fix;
	}
}
