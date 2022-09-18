(

// --------------------------------------------- CONFIG, GLOBALS --//
~netAddr = NetAddr("127.0.0.1", 5005); //OUT
~portID = 57122; // IN
thisProcess.openUDPPort(~portID);

~hwIns = 1;
~hwOut = 0;
~hwOuts = 16;
~pbOuts = 14;
~initLevel = 0.5;

ServerOptions.devices;
Server.default.options.numInputBusChannels = ~hwIns;
Server.default.options.numOutputBusChannels = ~hwOuts;
Server.default.options.sampleRate = 48000;
s.options.memSize = 65536;
s.reboot;

s.waitForBoot {

// --------------------------------------------- SAMPLE MGMT -----//

~pBuf = Buffer.read(s, thisProcess.nowExecutingPath.dirname +/+ "render.wav");

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

// --------------------------------------------- SYNTHDEFS ------//

SynthDef(\patchCord, {

	arg in, out, amp = 1;

	var input = In.ar(in, 1);
	Out.ar(out, input * amp)

}).add;

SynthDef(\klankSaw, { // filterbank ambience

	arg rate = 1, atk = 0.1, rel = 0.4, freq = 440, cutoff = 500, cutoff2 = 1500,
	pan = 0, amp = 0.2, fbank1 = 200, fbank2 = 671, fbank3 = 1153, fbank4 = 1723,
	out;

	var sig = KlankSaw.ar(rate, atk, rel, freq, cutoff, cutoff2, pan, amp, fbank1,
		fbank2, fbank3, fbank4);
	Out.ar(out, sig);

}).add;

SynthDef(\flicker, { // percussive sound

	arg rate = 1, atk = 0.1, rel = 0.4, freq = 440, cutoff = 500, cutoff2 = 1500,
	pan = 0, amp = 0.8, out;

	var sig = Flicker.ar(rate, atk, rel, freq, cutoff, cutoff2, pan, amp);
	Out.ar(out, sig);

}).add;

SynthDef(\hdVerb, { // nice sounding SC reverb

	arg in, out, predelay, decay, lpf1, lpf2;

	var sig = In.ar(in, 1);

	sig = Compander.ar(sig, sig, thresh: 0.5, slopeBelow: 1.0, slopeAbove: 0.25,
		clampTime: 0.01, relaxTime: 0.09);
	sig = HDVerb.ar(sig, predelay: predelay, decay: decay, lpf1: lpf1, lpf2: lpf2);
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
	wet = Decimator.ar(sig, bits: bit),
	freqs = Control.names([\freqs]).kr([800, 1071, 1153, 1723]),
    ringtimes = Control.names([\ringtimes]).kr([1, 1, 1, 1]),
	klang = DynKlank.ar(`[freqs, nil, ringtimes], wet * 0.5);
	wet = Mix.ar([klang * klangmix, wet * (1 - klangmix)]);

	wet = LPF.ar(wet, lcut);
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

s.sync;

// --------------------------------------------- BUS, PATCHING ---//

~dryBus = Array.fill(~pbOuts, { Bus.audio(s, 1)});
~fxBus = Array.fill(~pbOuts, { Bus.audio(s, 1)});
~mixBus = Array.fill(~pbOuts, { Bus.audio(s, 1)});
~outBus = Array.fill(~pbOuts, { Bus.audio(s, 1)});

~dryGroup = Group.tail(s);
~fxGroup = Group.tail(s);
~mixGroup = Group.tail(s);
~outGroup = Group.tail(s);

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

// --------------------------------------------- OPERATIONS ------//

OSCdef(\clientTrigger, {

	arg msg; msg.postln;

	if (msg[1] == 1, {

		~playback = Synth(\samplePlayer, [
			\out, ~dryBus[0], \buffer, ~pBuf, \trig, 1
		]);

	});

}, '/trigger');

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

~fFader = EZSlider.new(
	~w, Rect(20, 160, 430, 40),
	"dry",
	ControlSpec.new(0.0, 1.0, \lin, 0.01, 0, ""), {
		arg slider;
		~pbOuts.do {
			arg i;
			~drySynth[i].set(
				\amp,
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



})