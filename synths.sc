KlankSaw {

	* ar {

		arg rate = 1, atk = 0.1, rel = 0.4, freq = 440, cutoff = 500, cutoff2 = 1500,
		amp = 0.2, fbank1 = 200, fbank2 = 671, fbank3 = 1153, fbank4 = 1723, mul = 1,
		add = 0;

		var dust = Dust.ar(freq, 0.2),

		sig = Pulse.ar(freq) + Saw.ar(freq * 1.5, 0.5, 0.2) + dust,

		env = EnvGen.kr(
			Env.new(
				[0,1,0],
				[atk, rel],
				[1, -1]),
			doneAction:2),

		fenv = EnvGen.kr(
			Env.new(
				[cutoff,
					cutoff2,
					rrand(cutoff, cutoff2)],
				[atk, rel],
				[1, -1]),
			doneAction:2);

		sig = sig + (sig * dust);

		sig = BPF.ar(sig, fenv);

		sig = Klank.ar(`[[200, 671, 1153, 1723], nil, [1, 1, 1, 1]], (sig * env / 50));

		^sig * mul + add;

	}

}

Flicker {

	* ar {

		arg rate = 1, atk = 0.1, rel = 0.4, freq = 440, cutoff = 500, cutoff2 = 1500,
		amp = 0.8, mul = 1, add = 0;

		var sig = Dust.ar(freq, 0.8),

		env = EnvGen.kr(
			Env.new(
				[0,1,0],
				[atk, rel],
				[1, -1]),
			doneAction:2),

		fenv = EnvGen.kr(
			Env.new(
				[cutoff,
					cutoff2,
					rrand(cutoff, cutoff2)],
				[atk, rel],
				[1, -1]),
			doneAction:2);

		sig = BPF.ar(sig, fenv);

		^sig * mul + add;

	}

}

ChemFVerb {

	* ar {

		arg in, predelay = 1, decay = 10, lpf = 19500, pitchratio = 4.0, amp = 1, mul = 1,
		add = 0;

		var wet, temp, sig;

		temp = in;
		wet = 0;
		temp = DelayN.ar(
			temp,
			0.2,
			predelay);

		temp = PitchShift.ar(temp, 0.2, pitchratio, 1.1, 1.1, 2.2);

		temp = Compander.ar(temp, temp, 0.5, slopeBelow: 1.0, slopeAbove: 0.2);

		temp = HPF.ar(temp, 4000);

		16.do {
			temp = AllpassN.ar(
				temp,
				0.05,
				{Rand(0.001, 0.05)}!2,
				decay);
			temp - LPF.ar(temp, lpf);
			wet = wet + temp;
		};

		^ wet * mul + add;

	}

}

