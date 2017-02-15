block_size = 8;
adpcm_bits = 2;

[data_in, sample_rate] = load_input('snare-808', block_size);
audiowrite('orig.wav', data_in, sample_rate);

[bass_orig, bass_env_values, bass_cut_point, treble_orig, treble_env_fit, treble_b, treble_a] = separate(data_in, sample_rate, block_size);
audiowrite('bass_orig.wav', bass_orig, round(sample_rate/8));
audiowrite('treble_orig.wav', treble_orig, round(sample_rate/8));

bass_orig = bass_orig(1:bass_cut_point);
bass_env_values = bass_env_values(1:bass_cut_point);
audiowrite('bass_cut.wav', bass_orig, round(sample_rate/8));

bass_4bit = digitize_bass(bass_orig);
audiowrite('bass_4bit.wav', bass_4bit, round(sample_rate/8));

treble_recon = recon_treble(length(data_in), treble_env_fit, treble_b, treble_a, sample_rate);
audiowrite('treble_recon.wav', treble_recon, sample_rate);

bass_env_identity = ones(length(bass_env_values), 1);
bass_norm = bass_orig ./ bass_env_values;
% bass_norm = min(10, max(-10, bass_norm));
[bass_norm_adpcm, bass_norm_palette] = compress_adpcm(bass_norm, bass_env_identity, adpcm_bits);
bass_norm_recon = decompress_adpcm(bass_norm_adpcm, bass_norm_palette);
bass_recon = bass_norm_recon .* bass_env_values;
audiowrite('bass_recon.wav', bass_recon, round(sample_rate/8));

[bass_flat_adpcm, bass_flat_palette] = compress_adpcm(bass_orig, bass_env_identity, adpcm_bits);
bass_flat_recon = decompress_adpcm(bass_flat_adpcm, bass_flat_palette);
audiowrite('bass_flat_recon.wav', bass_flat_recon, round(sample_rate/8));


% mix and output
padding = zeros(length(data_in)/block_size - length(bass_orig), 1);
bass_orig_padded = [bass_orig; padding];
bass_recon_padded = [bass_recon; padding];
bass_flat_recon_padded = [bass_flat_recon; padding];
bass_upsampled = resample(bass_orig_padded, block_size, 1);
bass_recon_upsampled = resample(bass_recon_padded, block_size, 1);
bass_flat_recon_upsampled = resample(bass_flat_recon_padded, block_size, 1);
mix00 = bass_upsampled + treble_orig;
mix01 = bass_upsampled + treble_recon;
mix10 = bass_recon_upsampled + treble_orig;
mix11 = bass_recon_upsampled + treble_recon;
mix20 = bass_flat_recon_upsampled + treble_orig;
mix21 = bass_flat_recon_upsampled + treble_recon;
audiowrite('mix00.wav', mix00, sample_rate);
audiowrite('mix01.wav', mix01, sample_rate);
audiowrite('mix10.wav', mix10, sample_rate);
audiowrite('mix11.wav', mix11, sample_rate);
audiowrite('mix20.wav', mix20, sample_rate);
audiowrite('mix21.wav', mix21, sample_rate);


% Load wav-file
function [data, sample_rate] = load_input(stub, block_size)
	filename = ['in/'  stub  '.wav'];
	[data, sample_rate] = audioread(filename);
    padding = ceil(length(data) / block_size) * block_size - length(data); % pad
    data = [data zeros(padding, 1)]; % pad
    scaler = max(abs(data)); % normalize
    data = data / scaler; % normalize
end

% Prepare data for compression
function [bass_orig, bass_env_values, bass_cut_point, treble_orig, treble_env_fit, treble_b, treble_a] = separate(data_in, sample_rate, block_size)
	nyquist = sample_rate/2.0;
	separation_freq = nyquist/block_size/2.0;

    % separate and resample bass
    bass_orig = resample(data_in, 1, block_size);
    bass_orig = normalize(bass_orig);
    
	% separate treble
	[sep_treble_b, sep_treble_a] = butter(6, separation_freq / nyquist, 'high');
	treble_orig = filter(sep_treble_b, sep_treble_a, data_in);
	    
	% find volume envelopes
	bass_env = abs(hilbert(bass_orig));
	treble_env = abs(hilbert(treble_orig));

    % fit treble volume envelope
    treble_env_fit_x = (1:length(data_in))';
    treble_env_fit = fit(treble_env_fit_x, treble_env, 'exp2');
    
    % fit bass volume envelope
    bass_env_fit_x = (1:length(bass_orig))';
    bass_env_fit = fit(bass_env_fit_x, bass_env, 'exp2');
    bass_env_values = feval(bass_env_fit, bass_env_fit_x);
    
    % cut bass at the point where volume drops below 1/256
    % but also make sure envelope never goes below that point
    disp(max(bass_env_values));
    bass_cut_point = 0;
    limit = 1. / 2^10;
    for i = 1:length(bass_orig)
        if (bass_env_values(i) > limit)
            bass_cut_point = i;
        end
    end
    
    % extract treble color
    num_freqs = 1024;
    treble_h = fft(treble_orig, num_freqs);
    treble_h = treble_h(1:num_freqs/2+1);
    treble_w = (0:(num_freqs/2)) * (2*pi)/num_freqs;
    [treble_b, treble_a] = invfreqz(treble_h, treble_w, 2, 2);
    treble_ab_scaler = max(abs([treble_a(2:end) treble_b]));
    treble_a = treble_a / treble_ab_scaler;
    treble_b = treble_b / treble_ab_scaler;
end


% Run a simplified compression with given palette and return total error
function total_error = get_compression_error(data_in, palette, weights)
    total_error = 0;
    recon_1 = 0;
    recon_2 = 0;
    for i = 1:length(data_in)
        val = data_in(i);
        recon_slope = recon_1 - recon_2;
        prediction = recon_1 + recon_slope;
        if (prediction >= 0)
            palette_adj = -palette;
        else
            palette_adj = palette;
        end
        recon_opts = prediction + palette_adj;
        error_opts = (recon_opts - val) .^ 2;
        [error, index] = min(error_opts);
        error = error * weights(i);
        total_error = total_error + error;
        recon_2 = recon_1;
        recon_1 = recon_opts(index);
    end
end

% Run a simplified (for now) compression and return data
function data_out = compress_with_palette(data_in, palette)
    data_out = zeros(length(data_in), 1);
    recon_1 = 0;
    recon_2 = 0;
    for i = 1:length(data_in)
        val = data_in(i);
        recon_slope = recon_1 - recon_2;
        prediction = recon_1 + recon_slope;
        if (prediction >= 0)
            palette_adj = -palette;
        else
            palette_adj = palette;
        end
        recon_opts = prediction + palette_adj;
        error_opts = (recon_opts - val) .^ 2;
        [~, index] = min(error_opts);
        data_out(i) = index - 1;
        recon_2 = recon_1;
        recon_1 = recon_opts(index);
    end
end


function [palette, error] = find_palette(data_in, weights, bits)
    palette = zeros(1, 2^bits);
    error = get_compression_error(data_in, palette, weights);
    disp(['Initial: Error: ', num2str(error), ' Palette: ', num2str(palette)]);

    test_palette = palette;
    t = linspace(.5, -.25, 256*60);
    for temperature = t
        temperature_clamped = max(1./256, temperature);
        assert(test_palette(1) == 0); % keep it at 0
        test_palette(2:end) = palette(2:end) + randn(1, length(palette)-1) * temperature_clamped;
        test_palette(2:end) = max(-1.0, min(1.0, test_palette(2:end)));
        test_palette(2:end) = sort(test_palette(2:end));
        test_error = get_compression_error(data_in, test_palette, weights);
        if (test_error < error)
            error = test_error;
            palette = test_palette;
            disp(['Temperature: ', num2str(temperature), ' Error: ', num2str(error), ' Palette: ', num2str(palette)]);
        end
    end
end


function [data_out, palette_out] = compress_adpcm(data_in, weights, bits)
    [palette_out, ~] = find_palette(data_in, weights, bits);
    data_out = compress_with_palette(data_in, palette_out);
end

function data_out = decompress_adpcm(data_in, palette)
    data_out = zeros(length(data_in), 1);
    recon_1 = 0;
    recon_2 = 0;
    for i = 1:length(data_in)
        index = data_in(i);
        palette_val = palette(index+1);
        recon_slope = recon_1 - recon_2;
        prediction = recon_1 + recon_slope;
        if (prediction >= 0)
            palette_val = -palette_val;
        end
        recon = prediction + palette_val;
        data_out(i) = recon;
        recon_2 = recon_1;
        recon_1 = recon;
    end
end

% bass is in [-1:1]
function [res, scaler] = digitize_bass(val)
    bits = 4;

    % normalize
    scaler = max(abs(val));
    res = val / scaler;
    
    % digitize
    limit = 2 ^ bits;
    res = (res + 1.) * ((limit-1) / 2.);
    res = res + rand(size(res));
    res = round(res);
    res = min(limit-1, max(0.0, res));
    
    % for convenience
    res = ((res ./ (limit-1)) - 0.5) * 2;
end


function data_out = recon_treble(num_samples, env_fit, treble_b, treble_a, sample_rate)
    white = rand(num_samples, 1) * 2 - 1;

    colored = filter(treble_b, treble_a, white);
    colored = normalize(colored);

    env_fit_x = (1:num_samples);
    env_values = feval(env_fit, env_fit_x); 
    data_out = colored .* env_values;
end

function [data_out, scaler] = normalize(data_in) 
    scaler = max(abs(data_in));
    data_out = data_in / scaler;
end