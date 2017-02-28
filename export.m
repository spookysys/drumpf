function [ output_args ] = export(wav_filename, bass_data, palette, bass_env_fit, treble_b, treble_a, treble_env_fit)
    [data_fid, struct_fid, name] = start(wav_filename);
    
    % output bass_data
    if ~isempty(bass_data)
        bass_data_reshaped = reshape(bass_data, [4, length(bass_data)/4]);
        bass_data_packed = zeros(1, length(bass_data)/4);
        [~, num_bytes] = size(bass_data_reshaped);
        for i = 1:num_bytes
            tmp = bass_data_reshaped(:,i)';
            tmp = tmp .* [2^0 2^2 2^4 2^6];
            tmp = sum(tmp);
            bass_data_packed(i) = tmp;
        end
        fprintf(data_fid, '%.0f,' , bass_data_packed);
        clear bass_data_reshaped;
        clear bass_data_packed;
    end
    
    % output treble envelope
    export_env(struct_fid, treble_env_fit, 'treble envelope');

    % output treble filter
    export_filter(struct_fid, treble_b, treble_a);

    % output bass envelope
    export_env(struct_fid, bass_env_fit, 'bass envelope');
    
    % output bass palette
    if length(palette) ~= 4
        palette = [0 0 0 0];
    end
    fprintf(struct_fid, '{ %d, %d, %d, %d }, // bass palette\n', palette(1), palette(2), palette(3), palette(4));
    
    % pointer to bass data
    fprintf(struct_fid, [lower(name) '_data // bass data\n']);
    
    fclose(data_fid);
    fclose(struct_fid);
end

function export_env(fid, env_fit, comment)
    % a*exp(b*x) + c*exp(d*x)
    coeff = coeffvalues(env_fit);
    if length(coeff) ~= 4
        coeff = [0 0 0 0];
    end
    coeff(isnan(coeff)) = 0;
        
    % Rescale a and c
    volume_adj = [127.49 / max(coeff([1 3])) -128.49 / min(coeff([1 3]))];
    volume_adj = min(volume_adj(volume_adj > 0));
    scale_exp = floor(log2(volume_adj));
    scale_exp = min(scale_exp, 255);
    scales = max(-128, min(127, round(coeff([1 3]) * 2^scale_exp)));
    clear volume_adj;

    % Rescale decay
    decays = exp(coeff([2 4])*8);
    assert(all(decays >= 0 & decays <= 1));
    decays = decays * 256;
    decays = round(decays);
    decays = min(decays, 255);
    
    % Result
    fprintf(fid, '{ %d, %d, %d, %d, %d }, // %s\n', scale_exp, scales(1), scales(2), decays(1), decays(2), comment);
 end

function export_filter(fid, b, a)
    adj = [127.49 / max([1 b a]) -128.49 / min([1 b a])];
    adj = min(adj(adj > 0));
    ex = floor(log2(adj));
    adj = 2^ex;
    b_ = round(b * adj);
    a_ = round(a * adj);
    b_ = max(-128, min(127, b_));
    a_ = max(-128, min(127, a_));
    fprintf(fid, '{ %d, %d, %d, %d, %d, %d }, // treble filter\n' , ex, b_(1), b_(2), a_(1), a_(2), a_(3));
end

function [data_fid, struct_fid, name] = start(wav_filename)
     [~,~,~] = mkdir(fullfile('export', 'data'));
     [~,~,~] = mkdir(fullfile('export', 'struct'));
     [~, name, ~] = fileparts(wav_filename);
     name = lower(name);
     
     fid = fopen(fullfile('export', 'datas.inc'), 'a');
     fprintf(fid, [ '#ifdef INC_' upper(name) '\n']);
     fprintf(fid, [ 'const unsigned char ' name '_data[] = {\n']);
     fprintf(fid, [ '#include \"data/' name '.inc\"\n']);
     fprintf(fid, [ '};\n']);
     fprintf(fid, [ '#endif\n']);
     fclose(fid);
     clear fid;
     
     fid = fopen(fullfile('export', 'structs.inc'), 'a');
     fprintf(fid, [ '#ifdef INC_' upper(name) '\n']);
     fprintf(fid, [ '{\n']);
     fprintf(fid, [ '#include \"struct/' name '.inc\"\n']);
     fprintf(fid, [ '},\n']);
     fprintf(fid, [ '#endif\n']);
     fclose(fid);
     clear fid;     
          
     fid = fopen(fullfile('export', 'enums.inc'), 'a');
     fprintf(fid, [ '#ifdef INC_' upper(name) '\n']);
     fprintf(fid, [ upper(name) ',\n']);
     fprintf(fid, [ '#endif\n']);
     fclose(fid);
     clear fid;
          
     data_fid = fopen(fullfile('export', 'data', [name '.inc']), 'w');
     struct_fid = fopen(fullfile('export', 'struct', [name '.inc']), 'w');
end
