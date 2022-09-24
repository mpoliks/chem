thisProcess.removeOSCRecvFunc(~playbackDispatcher);

OSCFunc.trace

(

// --------------------------------------------- CONFIG, GLOBALS --//
thisProcess.openUDPPort(9270);

~hwIns = 1;
~hwOut = 0;
~hwOuts = 16;
~pbOuts = 14;
~subChannel = 14;
~players = 20;
~blobs = Dictionary.new;

~players.do( { arg n;
	~blobs.putAll(
		Dictionary[(n) -> Dictionary[ \alive -> true, \x -> 0, \x_ -> 0, \xv -> 0, \y -> 0, \z -> 0, \counter -> 0]]);
});

~zones = List.newClear(10);
~choir = Array.newClear(10);
~initLevel = 0.5;
~ftable = [55, 69.296, 82.41, 92.499, 103.83, 110, 123.47, 138.59, 155.745, 164.81, 184.998, 209.33, 220, 246.94, 330];
~p1 = List.newClear(2);
~counter = 0;
~state = \osc;

ServerOptions.devices;
Server.default.options.numInputBusChannels = ~hwIns;
Server.default.options.numOutputBusChannels = ~hwOuts;
Server.default.options.sampleRate = 48000;
s.options.memSize = 65536;
s.reboot;

"APP: LOADING ⬛⬜⬜⬜⬜".postln;

s.waitForBoot {

// --------------------------------------------- SAMPLE MGMT -----//

~pBuf = Buffer.read(s, thisProcess.nowExecutingPath.dirname +/+ "render.wav");

~ahBuf = Array.new;

a = PathName.new(
	thisProcess.nowExecutingPath.dirname
	+/+ "autoharp/");
a.entries.do({
	arg path;
	~ahBuf = ~ahBuf.add(Buffer.read(s, path.fullPath))});

SynthDef(\samplePlayer, {

	arg out = 0, atk = 20, rel = 1, buffer, loop = 0, trig, amp = 0.45;

	var env, sig;

	env = EnvGen.kr(
		Env.asr(atk, amp, rel),
		trig,
		doneAction: 2
	);

	sig = PlayBuf.ar(14, buffer, rate: 1, loop: loop, doneAction: 2);
	sig = (sig * env * amp);
	Out.ar(out, sig);

}).add;

SynthDef(\mPlayer, {

	arg rate = 1, atk = 0.1, rel = 0.4, cutoff = 500, buf, rq = 4.0, amp = 1.0, out;

	var sig = PlayBuf.ar(
		1,
		buf,
		BufRateScale.ir(buf) * rate,
		doneAction: 2),

	env = EnvGen.kr(
			Env.new(
				[0,1,0],
				[atk, rel],
				[1, -1]),
			doneAction:2);

	sig = BPF.ar(sig, cutoff);

	Out.ar(out, sig * env);

}).add;

// --------------------------------------------- SYNTHDEFS ------//

SynthDef(\patchCord, {

	arg in, out, amp = 1;

	var input = In.ar(in, 1);
	Out.ar(out, input * amp)

}).add;

SynthDef(\klankSaw, { // filterbank ambience

	arg rate = 1, atk = 5.0, rel = 6.0, freq = 440, cutoff = 200, fbank = 400,
	pan = 0, amp = 0.1, trig = 0, out, fxout;

	var freqs = Control.names([\freqs]).kr([800, 1071, 1153, 1723]),
    ringtimes = Control.names([\ringtimes]).kr([1, 1, 1, 1]), klang, temp,

	env = EnvGen.kr(
		Env.asr(atk, amp, rel),
		trig,
		doneAction: 2
	),

	sig = Mix.ar([
		Pulse.ar(((0.5 * freq) + WhiteNoise.ar(2.0)), WhiteNoise.ar(0.01), 0.7) +
		Pulse.ar((freq + WhiteNoise.ar(2.0)) * 1.0001, WhiteNoise.ar(4.0), 0.3),
		Pulse.ar(freq * 1.9999, WhiteNoise.ar(1.0), 0.1),
		SinOsc.ar(freq * 0.5),
		PinkNoise.ar(0.01),
		//Dust.ar(0.04, 0.3),
		Saw.ar(freq * 2.750, 0.002),
		Saw.ar(freq * 1.499, 0.003)]);

	klang = DynKlank.ar(`[freqs, nil, ringtimes], sig * 0.5) * 0.001;

	temp = PitchShift.ar(sig, 0.2, 1.0001, 0.01, 0.02, 0.2);

	sig = Mix.ar([sig, klang, temp]);

	sig = Decimator.ar(sig, bits: 8);

	sig = RLPF.ar(sig, cutoff);

	sig = BPF.ar(sig, fbank);

	temp = CombN.ar(sig, 0.4, 0.4, 1.0, 0.6);

	sig = Mix.ar([sig, klang, temp]);

	klang = CombN.ar(sig, 0.6, Dust.kr(1, 0.6), 1.3, 0.4);

	32.do({ arg o,
			sig = AllpassN.ar(sig, 0.01, XLine.kr(0.0001, 0.01, 20), 7);
		});

	sig = Compander.ar(sig, sig, thresh: 0.25, slopeBelow: 1.0, slopeAbove: 0.125,
		clampTime: 0.01, relaxTime: 0.09);

	sig = BLowShelf.ar(sig, freq: 480.0, rs: 1.0, db: 15.0, mul: 1.0, add: 0.0);

	Out.ar(out, sig * 0.75 * amp * env);

	Out.ar(~subChannel, sig * 0.4 * amp * env);

	Out.ar(fxout, sig * 2.5 * amp * env);

}).add;

SynthDef(\flicker, { // percussive sound

	arg rate = 1, atk = 0.1, rel = 0.4, freq = 440, cutoff = 500, cutoff2 = 1500,
	pan = 0, amp = 0.8, out;

	var sig = Flicker.ar(rate, atk, rel, freq, cutoff, cutoff2, pan, amp);
	Out.ar(out, sig);

}).add;

SynthDef(\freezeVerb, { // freeze reverb

	arg in, out, amp = 1, predelay, decay;

	var sig = In.ar(in, 1);

	sig = Compander.ar(sig, sig, thresh: 0.5, slopeBelow: 1.0, slopeAbove: 0.25,
		clampTime: 0.01, relaxTime: 0.09);
	sig = ChemFVerb.ar(sig, predelay: predelay, decay: decay);
	Out.ar(out, sig * amp);

}).add;

SynthDef(\dryIO, { // compressor on the dry bus

	arg out = 0, fxout = 0, in = 0, amp = 1, lcut = 20000, hcut = 30, bit = 24, klangmix = 0.0, mix = 0.1, revmix = 0;

	var sig = In.ar(in, 1), sum,

	dry = sig,

	wet = LPF.ar(dry, lcut);
	wet = HPF.ar(wet, hcut);
	sum = Mix.ar([dry * (1 - mix), wet * mix]);

	sum = Compander.ar(sum, sum, thresh: 0.4, slopeBelow: 1.0, slopeAbove: 0.25,
		clampTime: 0.01, relaxTime: 0.09);

	Out.ar(out, sum * amp);
	Out.ar(fxout, sum * revmix);

}).add;

SynthDef(\mixIO, { // compressor and limiter on the mix bus

	arg out = 0, in = 0, amp = 1;

	var sig = In.ar(in, 1);

	sig = Compander.ar(sig, sig, thresh: 0.5, slopeBelow: 1.0, slopeAbove: 0.25,
		clampTime: 0.01, relaxTime: 0.01);
	sig = Limiter.ar(sig, level: 0.8, dur: 0.1);
	Out.ar(out, sig * amp);

}).add;

"APP: LOADING ⬛⬛⬜⬜⬜".postln;

s.sync;

// --------------------------------------------- BUS, PATCHING ---//

~dryBus = Array.fill(~pbOuts, { Bus.audio(s, 1)});
~fxBus = Array.fill(~pbOuts, { Bus.audio(s, 1)});
~mixBus = Array.fill(~pbOuts, { Bus.audio(s, 1)});
~outBus = Array.fill(~pbOuts, { Bus.audio(s, 1)});
~subBus =  Array.fill(~pbOuts, { Bus.audio(s, 1)});

~dryGroup = Group.tail(s);
~synthGroup = Group.tail(s);
~fxGroup = Group.tail(s);
~mixGroup = Group.tail(s);
~outGroup = Group.tail(s);
~subGroup = Group.tail(s);

"APP: LOADING ⬛⬛⬛⬜⬜".postln;

~drySynth = Array.fill(~pbOuts, {

	arg i;

	Synth( \dryIO, [
		\in, ~dryBus[i], \out, ~mixBus[i], \fxout, ~fxBus[i]
	], ~dryGroup);

});


~fxSynth = Array.fill(~pbOuts, {

	arg i;

	Synth(\freezeVerb, [
			\in, ~fxBus[i], \decay, 13, \predelay, 1.0, \out, ~mixBus[i]
	], ~fxGroup);

});


~mixSynth = Array.fill(~pbOuts, {

	arg i;

	Synth(\mixIO, [
		\in, ~mixBus[i], \out, ~outBus[i]
	], ~mixGroup);

});

~outSynth = Array.fill(~pbOuts, {

	arg i;

	Synth(\patchCord, [
		\in, ~outBus[i], \out, ~hwOut + i
	], ~outGroup);

});

s.sync;

"APP: LOADING ⬛⬛⬛⬛⬜".postln;

// --------------------------------------------- OPERATIONS ------//

OSCdef(\clientTrigger, {

	arg msg; msg.postln;

	if (msg[1] == 1, {

		~playback = Synth(\samplePlayer, [
			\out, ~dryBus, \buffer, ~pBuf, \trig, 1
		]);

	});

}, '/trigger');


thisProcess.removeOSCRecvFunc(~playbackDispatcher);

s.sync;

~playbackDispatcher = {

	arg msg;

	var addr = msg[0].asString, player, counter, alive, zone, map;

	if("Pelvis".matchRegexp(addr), {

		var n1 = ((addr)[2]).asString, n2 = ((addr)[3]).asString, z = List.newClear(10);

		if (n2.matchRegexp("/"), { player = n1.asInteger; },
			{ player = (n1.asInteger * 10) + n2.asInteger; });
			//player.postln;

		player = player - 1;

		counter = (~blobs.at(player).at(\counter) + 1) % 100;
		~blobs.at(player).add(\counter -> counter);

		if(":tx".matchRegexp(addr), { ~blobs.at(player).add(\x -> msg[1].asFloat); });
		if (counter == 0, {
				~blobs.at(player).add(\xv -> (
					~blobs.at(player).at(\x) - ~blobs.at(player).at(\x_)
				).abs);
				~blobs.at(player).add(\x_ -> msg[1].asFloat);
				//~blobs.at(player).at(\xv).postln;
			});

		if(":ty".matchRegexp(addr), { ~blobs.at(player).add(\y -> msg[1].asFloat); });

		if(":tz".matchRegexp(addr), { ~blobs.at(player).add(\z -> msg[1].asFloat); });

		z[9] = ~blobs.at(player).at(\x).gaussCurve(1.0, 1.0, 0.1) + ~blobs.at(player).at(\y).gaussCurve(1.0, 0.0, 0.1);
		z[0] = ~blobs.at(player).at(\x).gaussCurve(1.0, 0.6, 0.1) + ~blobs.at(player).at(\y).gaussCurve(1.0, -0.5, 0.1);
		z[1] = ~blobs.at(player).at(\x).gaussCurve(1.0, 0.2, 0.1) + ~blobs.at(player).at(\y).gaussCurve(1.0, -0.5, 0.1);
		z[2] = ~blobs.at(player).at(\x).gaussCurve(1.0, -0.2, 0.1) + ~blobs.at(player).at(\y).gaussCurve(1.0, -0.5, 0.1);
		z[3] = ~blobs.at(player).at(\x).gaussCurve(1.0, -0.6, 0.1) + ~blobs.at(player).at(\y).gaussCurve(1.0, -0.5, 0.1);
		z[4] = ~blobs.at(player).at(\x).gaussCurve(1.0, -1.0, 0.1) + ~blobs.at(player).at(\y).gaussCurve(1.0, 0.0, 0.1);
		z[5] = ~blobs.at(player).at(\x).gaussCurve(1.0, -0.6, 0.1) + ~blobs.at(player).at(\y).gaussCurve(1.0, 0.5, 0.1);
		z[6] = ~blobs.at(player).at(\x).gaussCurve(1.0, -0.2, 0.1) + ~blobs.at(player).at(\y).gaussCurve(1.0, 0.5, 0.1);
		z[7] = ~blobs.at(player).at(\x).gaussCurve(1.0, 0.2, 0.1) + ~blobs.at(player).at(\y).gaussCurve(1.0, 0.5, 0.1);
		z[8] = ~blobs.at(player).at(\x).gaussCurve(1.0, 0.6, 0.1) + ~blobs.at(player).at(\y).gaussCurve(1.0, 0.5, 0.1);


		~blobs.at(player).add(\map -> z);
		~blobs.at(player).add(\zone -> z.maxIndex);

		alive = ~blobs.at(player).at(\alive);
		zone = ~blobs.at(player).at(\zone);
		map = ~blobs.at(player).at(\map);


			switch( ~state,

				\idle, { },

				\osc, {

					if (alive == false, { ~blobs.at(player).at(\synth).set(\trig, 0); },

					{
						if ((zone != ~blobs.at(player).at(\zone_)), {
							~blobs.at(player).add(\zone_ -> zone);
							~blobs.at(player).at(\zone).postln;
							~blobs.at(player).at(\synth).set(\trig, 0);
							~blobs.at(player).add(\synth ->
								Synth(\klankSaw, [
									\out, ~dryBus[zone],
									\fxout, ~fxBus[zone],
									\freq, ~ftable[15.rand],
									\trig, 1,
									\amp, 0.4
								], ~dryGroup ); ); });

						if ((~blobs.at(player).at(\synth).notNil), {
							~blobs.at(player).at(\synth).set(\cutoff, map[zone].linlin(0, 2, 200, 16000));
							~blobs.at(player).at(\synth).set(\fbank, ~blobs.at(player).at(\z)
									.linlin(-1.0, 1.0, 100, 3800, clip:\minmax));
						});
					});

				},

			\autoharp, {

				if (((counter == 0) && (~blobs.at(player).at(\xv) > 1.1)), {

					var z = rrand(0, 9);

					"trig".postln;

					Pbind( \instrument, \mPlayer, \env, 1,
					\dur, Pwhite(0.01, 0.3, rrand(2, 12)),
					\cutoff, Pwhite(800, 16000),
					\buf, Pshuf(~ahBuf, inf),
					\out, Pseq(
						[~dryBus[~blobs.at(player).at(\zone)],
						~fxBus[~blobs.at(player).at(\zone)]], inf);

				).play; });

			},

			\filters, { },

		);

	});

};

s.sync;

thisProcess.addOSCRecvFunc(~playbackDispatcher);


// --------------------------------------------- GUI -------------//

Window.closeAll;
s.meter (~hardwareInputs, ~hardwareOutputs);

~w = Window("GUI Controls", Rect(0,-100,550,550))
	.front.alwaysOnTop_(true);
~w.view.decorator_(FlowLayout(~w.bounds, 10@10, 10@10));

~channelLevels = Array.fill(~pbOuts, {

	arg p;

	var r = EZSlider.new(
	~w, 210@16,
	p.asString,
	ControlSpec.new(0.00, 1.0, \lin, 0.01, 0, ""), {
		arg slider;
		~mixSynth[p].set(
			\amp,
			slider.value)
		}, 1.0, false, 30, 30).value_(1.0)
	.setColors(Color.grey,Color.white);

});

~masterFader = EZSlider.new(
	~w, Rect(20, 160, 430, 40),
	"Master",
	ControlSpec.new(0.00, 1.0, \lin, 0.01, 0, ""), {
		arg slider;
		~pbOuts.do {
			arg i;
			~outSynth[i].set(
				\amp,
				slider.value)
			};
		}, 1.0, false, 80, 45).value_(~initLevel)
	.setColors(Color.grey,Color.white);

~mixFader = EZSlider.new(
	~w, Rect(20, 160, 430, 40),
	"mix",
	ControlSpec.new(0.00, 1.0, \lin, 0.01, 0, ""), {
		arg slider;
		~pbOuts.do {
			arg i;
			~drySynth[i].set(
				\mix,
				slider.value)
			};
		}, 0, false, 80, 45).value_(~initLevel)
	.setColors(Color.grey,Color.white);

~mixFader = EZSlider.new(
	~w, Rect(20, 160, 430, 40),
	"mix",
	ControlSpec.new(0.00, 1.0, \lin, 0.01, 0, ""), {
		arg slider;
		~pbOuts.do {
			arg i;
			~drySynth[i].set(
				\klangmix,
				slider.value)
			};
		}, 0, false, 80, 45).value_(~initLevel)
	.setColors(Color.grey,Color.white);

~fFader = EZSlider.new(
	~w, Rect(20, 160, 430, 40),
	"filter",
	ControlSpec.new(1, 5, \lin, 0.01, 1, ""), {
		arg slider;
		~pbOuts.do {
			arg i;
			~drySynth[i].setn(
				\freqs,
				[slider.value * 800, slider.value * 1071, slider.value * 1153, slider.value * 1724])
			};
		}, 0, false, 80, 45).value_(~initLevel)
	.setColors(Color.grey,Color.white);

~fFader = EZSlider.new(
	~w, Rect(20, 160, 430, 40),
	"rev",
	ControlSpec.new(0.0, 1.0, \lin, 0.01, 0, ""), {
		arg slider;
		~pbOuts.do {
			arg i;
			~drySynth[i].set(
				\revmix,
				slider.value)
			};
		}, 0, false, 80, 45).value_(0.0)
	.setColors(Color.grey,Color.white);

b = Button(~w, Rect(20, 20, 340, 30))
	.states_([
		["Manually Trigger Audio", Color.black, Color.grey],
		["Audio Off", Color.white, Color.grey],
	])
	.action_({
		|state|
		~targetOverride = true;
		switch(state.value,
			1, {
				~playback = Synth(\samplePlayer, [
					\out, ~dryBus[0], \buffer, ~pBuf, \trig, 1]);
			},
			0, {
				~playback.set(
					\trig, 0);
			}
		);
	});

b = Button(~w, Rect(20, 20, 340, 30))
	.states_([
		["Autoharp Test", Color.black, Color.grey],
		["Test Off", Color.white, Color.grey],
	])
	.action_({
		|state|
		~targetOverride = true;
		switch(state.value,
			1, {

				var z = rrand(0, 9);

				Pbind(
					\instrument, \mPlayer,
					\env, 1,
					\dur, Pwhite(0.01, 0.3, rrand(2, 12)),
					\cutoff, Pwhite(300, 3000),
					\buf, Pshuf(~ahBuf, inf),
					\out, Pseq([~dryBus[0], ~fxBus[0]], inf);
				).play;
			},

			0, {
				~playback.set(
					\trig, 0);
			}
		);
	});

b = Button(~w, Rect(20, 20, 340, 30))
	.states_([
		["Saw Test", Color.black, Color.grey],
		["Test Off", Color.white, Color.grey],
	])
	.action_({
		|state|
		~targetOverride = true;
		switch(state.value,
			1, {

				var z = rrand(0, 9),
				f = rrand(0, ~ftable.size);

				Pbind(
					\instrument, \klankSaw,
					\env, 1,
					\dur, Pwhite(1, 10, rrand(2, 12)),
					\freq, ~ftable[f],
					\cutoff, Env(
						[800, 16000, 800],
						[20.0, 38.0],
						\sin),
					\fbank, Env(
						[200, 16000, 7000],
						[33.0, 26.0],
						\sin),
					\fxout, Pseq([
						~fxBus[0],
						~fxBus[1],
						~fxBus[2],
						~fxBus[3],
						~fxBus[4],
						~fxBus[5],
						~fxBus[6],
						~fxBus[7],
						~fxBus[8],
						~fxBus[9]], inf),
					\out, Pseq([
						~dryBus[0],
						~dryBus[1],
						~dryBus[2],
						~dryBus[3],
						~dryBus[4],
						~dryBus[5],
						~dryBus[6],
						~dryBus[7],
						~dryBus[8],
						~dryBus[9]], inf)
				).play;
			},

			0, {
			}
		);
	});

"APP: LOADED  ⬛⬛⬛⬛⬛ ----- COMPLETE".postln;

})