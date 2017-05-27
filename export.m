function export(wav_filename, bass_data, treble_b, treble_a, treble_env_fit)
    [data_fid, struct_fid, name] = start(wav_filename, ~isempty(bass_data));
    
    % output bass data
    export_bass_data(data_fid, bass_data);
    
    % output treble envelope
    export_env(struct_fid, treble_env_fit, 'treble envelope');

    % output treble filter
    export_filter(struct_fid, treble_b, treble_a);

    % bass start
    fprintf(struct_fid, '{\n');
    
    % bass data
    fprintf(struct_fid, ['    sizeof(' lower(name) '_data),\n']);
    fprintf(struct_fid, ['    ' lower(name) '_data // bass data\n']);
    
    % bass end
    fprintf(struct_fid, '}\n');
    
    fclose(data_fid);
    fclose(struct_fid);
end

function export_bass_data(fid, bass_data)
    if ~isempty(bass_data)
        bass_data_reshaped = reshape(bass_data, [4, length(bass_data)/4]);
        bass_data_packed = zeros(1, length(bass_data)/4);
        [~, num_bytes] = size(bass_data_reshaped);
        for i = 1:num_bytes
            tmp1 = bass_data_reshaped(:,i)' - 1;
            tmp2 = tmp1 .* [2^0 2^2 2^4 2^6];
            tmp3 = sum(tmp2);
            bass_data_packed(i) = tmp3;
        end
        fprintf(fid, '%.0f,' , bass_data_packed);
    end
end

function export_env(fid, env_fit, comment)
    coeff = coeffvalues(env_fit);
    if length(coeff) ~= 2
        coeff = [0 0];
    end
    coeff(isnan(coeff)) = 0;
        
    digi = round(coeff .* [-2^(19) 2^(8)]);
    
    % Result
    fprintf(fid, '// %.16f, %.16f // %s floats\n', coeff(1), coeff(2), comment);
    fprintf(fid, '{ %d, %d }, // %s\n', digi(1), digi(2), comment);
 end

function export_filter(fid, b, a)
    ex = 6; % empirical
    tmp = [a b];
    tmp = tmp .* [0 64 128 256 256 128];
    tmp = round(tmp);
    tmp = max(-128, min(127, tmp));
    fprintf(fid, '// %f, %f, %f, %f, %f, %f // treble filter floats\n' , a(1), a(2), a(3), b(1), b(2), b(3));
    fprintf(fid, '{ %d, %d, %d, %d, %d }, // treble filter\n' , tmp(2), tmp(3), tmp(4), tmp(5), tmp(6));
end

function [data_fid, struct_fid, name] = start(wav_filename, has_bass_data)
     [~,~,~] = mkdir(fullfile('export', 'data'));
     [~,~,~] = mkdir(fullfile('export', 'struct'));
     [~, name, ~] = fileparts(wav_filename);
     name = lower(name);
     name = regexprep(name, '[^\w]', '_');
     
     fid = fopen(fullfile('export', 'use_all.inc'), 'a');
     fprintf(fid, [ '#define USE_' upper(name) '\n']);
     fclose(fid);
     clear fid;
     
     fid = fopen(fullfile('export', 'names.inc'), 'a');
     fprintf(fid, [ '"' lower(name) '",\n']);
     fclose(fid);
     clear fid;
     
     fid = fopen(fullfile('export', 'datas.inc'), 'a');
     fprintf(fid, [ '#ifdef USE_' upper(name) '\n']);
     if has_bass_data
         fprintf(fid, [ 'const unsigned char ' name '_data[] = {\n']);
         fprintf(fid, [ '#include \"data/' name '.inc\"\n']);
         fprintf(fid, [ '};\n']);
     else
         fprintf(fid, [ 'static const unsigned char* ' name '_data = nullptr;\n']);
     end
     fprintf(fid, [ '#endif\n']);
     fclose(fid);
     clear fid;     
     
     fid = fopen(fullfile('export', 'structs.inc'), 'a');
     fprintf(fid, [ '#ifdef USE_' upper(name) '\n']);
     fprintf(fid, [ '{\n']);
     fprintf(fid, [ '#include \"struct/' name '.inc\"\n']);
     fprintf(fid, [ '},\n']);
     fprintf(fid, [ '#endif\n']);
     fclose(fid);
     clear fid;     
          
     fid = fopen(fullfile('export', 'enums.inc'), 'a');
     fprintf(fid, [ '#ifdef USE_' upper(name) '\n']);
     fprintf(fid, [ upper(name) ',\n']);
     fprintf(fid, [ '#endif\n']);
     fclose(fid);
     clear fid;
          
     data_fid = fopen(fullfile('export', 'data', [name '.inc']), 'w');
     struct_fid = fopen(fullfile('export', 'struct', [name '.inc']), 'w');
end
