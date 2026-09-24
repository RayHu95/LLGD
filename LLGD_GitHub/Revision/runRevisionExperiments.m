function [summary, detail, config] = runRevisionExperiments(datasetFiles, config)
    codeRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(genpath(fullfile(codeRoot, 'LineDetection')));
    addpath(genpath(fullfile(codeRoot, 'frameGT')));
    addpath(fileparts(mfilename('fullpath')));

    if nargin < 1 || isempty(datasetFiles)
        datasetFiles = {fullfile(codeRoot, 'datasets', 'shapes_6dof_events.mat'), ...
            fullfile(codeRoot, 'datasets', 'urban_events.mat'), ...
            fullfile(codeRoot, 'datasets', 'office_spiral_events.mat')};
    elseif ischar(datasetFiles) || isstring(datasetFiles)
        datasetFiles = cellstr(datasetFiles);
    end
    defaults = defaultConfiguration(codeRoot);
    if nargin < 2 || isempty(config)
        config = defaults;
    else
        config = mergeConfiguration(defaults, config);
    end
    grid = config.grid;
    cases = buildCases(config, grid);
    cases = cases(ismember({cases.Category}, config.categories));
    rng(config.seed, 'twister');

    rows = repmat(emptyDetailRow(), 0, 1);
    rowNum = 0;
    for datasetIdx = 1:numel(datasetFiles)
        datasetFile = resolveDatasetFile(datasetFiles{datasetIdx}, codeRoot);
        loaded = load(datasetFile);
        data = loaded.data;
        [eHeight, eWidth] = obtainSensorSize(loaded, data);
        packetNum = min(numel(data), config.maxPackets);
        baseline = buildFrameBaseline(data(1:packetNum));
        [~, datasetName] = fileparts(datasetFile);

        if packetNum > 0
            for warmupIdx = 1:config.runtimeWarmup
                detectEvents(double(data(1).events), config.detectorParameters, eWidth, eHeight);
            end
        end

        fprintf('\n[%s] %d event arrays\n', datasetName, packetNum);
        for packetIdx = 1:packetNum
            eventArray = double(data(packetIdx).events);
            baselineLabels = baseline(packetIdx).labels;
            for caseIdx = 1:numel(cases)
                currentCase = cases(caseIdx);
                for repeatIdx = 1:currentCase.Repeats
                    rng(config.seed + 100000 + packetIdx * 1000 + ...
                        repeatIdx, 'twister');
                    [testEvents, testBaseline] = perturbEvents(eventArray, baselineLabels, ...
                        currentCase.KeepRatio, currentCase.NoiseRatio);
                    [predictedLabels, runtime] = detectEvents(testEvents, ...
                        currentCase.Parameters, eWidth, eHeight);
                    metrics = evaluateEventLabels(testBaseline, predictedLabels);

                    rowNum = rowNum + 1;
                    rows(rowNum, 1) = emptyDetailRow();
                    rows(rowNum).Dataset = string(datasetName);
                    rows(rowNum).Packet = packetIdx;
                    rows(rowNum).Experiment = string(currentCase.Name);
                    rows(rowNum).Category = string(currentCase.Category);
                    rows(rowNum).Parameter = string(currentCase.Parameter);
                    rows(rowNum).Value = currentCase.Value;
                    rows(rowNum).Repeat = repeatIdx;
                    rows(rowNum).EventCount = numel(testBaseline);
                    rows(rowNum).LineCount = metrics.lineCount;
                    rows(rowNum).ClusterCount = metrics.clusterCount;
                    rows(rowNum).Coverage = metrics.coverage;
                    rows(rowNum).Precision = metrics.precision;
                    rows(rowNum).F1 = metrics.F1;
                    rows(rowNum).IoU = metrics.IoU;
                    rows(rowNum).Fragmentation = metrics.fragmentation;
                    rows(rowNum).MergeError = metrics.mergeError;
                    rows(rowNum).ExtraEventRatio = metrics.extraEventRatio;
                    rows(rowNum).RuntimeSeconds = runtime;
                end
            end
        end
    end

    detail = struct2table(rows);
    summary = summarizeResults(detail);
    if ~isfolder(config.outputFolder)
        mkdir(config.outputFolder);
    end
    detailFile = fullfile(config.outputFolder, [config.resultPrefix, '_detail.csv']);
    summaryFile = fullfile(config.outputFolder, [config.resultPrefix, '_summary.csv']);
    matFile = fullfile(config.outputFolder, [config.resultPrefix, '_results.mat']);
    writetable(detail, detailFile);
    writetable(summary, summaryFile);
    save(matFile, 'summary', 'detail', 'config', 'datasetFiles', '-v7.3');
    fprintf('\nSaved revision results to %s\n', config.outputFolder);
end

function config = defaultConfiguration(codeRoot)
    config.seed = 2025;
    config.maxPackets = 30;
    config.runtimeRepeats = 3;
    config.perturbationRepeats = 5;
    config.runtimeWarmup = 1;
    config.categories = {'Full', 'Ablation', 'Sensitivity', ...
        'Sparsity', 'AddedEvents', 'Runtime'};
    config.outputFolder = fullfile(codeRoot, 'Revision', 'results');
    config.resultPrefix = 'revision';
    config.detectorParameters = struct('MADThreshold', 3.5, ...
        'PinThreshold', 0.8, 'PwThreshold', 0.8, ...
        'OverlapThreshold', 0.8, 'Eps1', 0.02, 'Eps2', 0.02, ...
        'UseWeights', true, 'UseVerification', true, ...
        'UseGlobalExpansion', true);
    config.grid = struct('MADThreshold', [3.0, 3.5, 4.0], ...
        'PinThreshold', [0.7, 0.8, 0.9], ...
        'PwThreshold', [0.7, 0.8, 0.9], ...
        'OverlapThreshold', [0.7, 0.8, 0.9], ...
        'Eps1', [0.015, 0.020, 0.025], ...
        'Eps2', [0.005, 0.010, 0.015, 0.020, 0.025], ...
        'SparseKeepRatio', [0.25, 0.50, 0.75], ...
        'NoiseRatio', [0.05, 0.10, 0.20, 0.30]);
end

function cases = buildCases(config, grid)
    base = config.detectorParameters;
    cases = repmat(newCase('', '', '', NaN, base, 1, 0, 1), 0, 1);
    cases(end+1, 1) = newCase('Full LLGD', 'Full', '-', NaN, base, 1, 0, 1);

    ablation = {'UseWeights', 'w/o weighted support'; ...
        'UseVerification', 'w/o local verification'; ...
        'UseGlobalExpansion', 'w/o global expansion'};
    for i = 1:size(ablation, 1)
        parameters = base;
        parameters.(ablation{i, 1}) = false;
        cases(end+1, 1) = newCase(ablation{i, 2}, 'Ablation', ...
            ablation{i, 1}, 0, parameters, 1, 0, 1);
    end

    parameters = base;
    parameters.UseWeights = false;
    parameters.UseMultiplicitySupport = true;
    cases(end+1, 1) = newCase('unit estimation weights', 'Ablation', ...
        'UseWeights', 0, parameters, 1, 0, 1);
    parameters = base;
    parameters.UseWeights = true;
    parameters.UseMultiplicitySupport = false;
    cases(end+1, 1) = newCase('unit support tests', 'Ablation', ...
        'UseMultiplicitySupport', 0, parameters, 1, 0, 1);

    sensitivity = {'MADThreshold', 'MAD'; 'PinThreshold', 'p_in'; ...
        'PwThreshold', 'p_w'; 'OverlapThreshold', 'overlap'; ...
        'Eps1', 'eps_s'; 'Eps2', 'eps_t'};
    for i = 1:size(sensitivity, 1)
        values = grid.(sensitivity{i, 1});
        for j = 1:numel(values)
            parameters = base;
            parameters.(sensitivity{i, 1}) = values(j);
            name = sprintf('%s = %.4g', sensitivity{i, 2}, values(j));
            cases(end+1, 1) = newCase(name, 'Sensitivity', sensitivity{i, 2}, ...
                values(j), parameters, 1, 0, 1);
        end
    end

    for i = 1:numel(grid.SparseKeepRatio)
        value = grid.SparseKeepRatio(i);
        name = sprintf('Event retention = %.0f%%', 100 * value);
        cases(end+1, 1) = newCase(name, 'Sparsity', 'retention', ...
            value, base, value, 0, config.perturbationRepeats);
    end
    for i = 1:numel(grid.NoiseRatio)
        value = grid.NoiseRatio(i);
        name = sprintf('Added events = %.0f%%', 100 * value);
        cases(end+1, 1) = newCase(name, 'AddedEvents', 'added-event ratio', ...
            value, base, 1, value, config.perturbationRepeats);
    end
    cases(end+1, 1) = newCase('Full LLGD runtime', 'Runtime', '-', NaN, ...
        base, 1, 0, config.runtimeRepeats);
end

function currentCase = newCase(name, category, parameter, value, parameters, keepRatio, noiseRatio, repeats)
    currentCase = struct('Name', name, 'Category', category, ...
        'Parameter', parameter, 'Value', value, 'Parameters', parameters, ...
        'KeepRatio', keepRatio, 'NoiseRatio', noiseRatio, 'Repeats', repeats);
end

function [labels, runtime] = detectEvents(eventArray, parameters, eWidth, eHeight)
    if isempty(eventArray)
        labels = zeros(0, 1);
        runtime = 0;
        return;
    end
    tic;
    timestamp = double(eventArray(:, 4)) + double(eventArray(:, 5)) / 1e9;
    pointData = [double(eventArray(:, 1)) / double(eWidth), ...
        double(eventArray(:, 2)) / double(eHeight), timestamp - timestamp(1)];
    detector = EventLineDBSCAN();
    detector.pointData = pointData;
    detector.c_width = double(eWidth);
    detector.c_height = double(eHeight);
    names = fieldnames(parameters);
    for i = 1:numel(names)
        detector.(names{i}) = parameters.(names{i});
    end
    labels = detector.EventSegmentation();
    runtime = toc;
    labels = labels(:);
end

function [eventArray, baselineLabels] = perturbEvents(eventArray, baselineLabels, keepRatio, noiseRatio)
    baselineLabels = baselineLabels(:);
    if keepRatio < 1 && ~isempty(eventArray)
        keepNum = max(1, round(keepRatio * size(eventArray, 1)));
        keepIdx = sort(randperm(size(eventArray, 1), keepNum));
        eventArray = eventArray(keepIdx, :);
        baselineLabels = baselineLabels(keepIdx);
    end
    noiseNum = round(noiseRatio * size(eventArray, 1));
    if noiseNum == 0 || isempty(eventArray)
        return;
    end

    timestamp = eventArray(:, 4) + eventArray(:, 5) / 1e9;
    noise = zeros(noiseNum, size(eventArray, 2));
    noise(:, 1) = round(min(eventArray(:, 1)) + ...
        (max(eventArray(:, 1)) - min(eventArray(:, 1))) * rand(noiseNum, 1));
    noise(:, 2) = round(min(eventArray(:, 2)) + ...
        (max(eventArray(:, 2)) - min(eventArray(:, 2))) * rand(noiseNum, 1));
    polarity = unique(eventArray(:, 3));
    noise(:, 3) = polarity(randi(numel(polarity), noiseNum, 1));
    noiseTime = min(timestamp) + (max(timestamp) - min(timestamp)) * rand(noiseNum, 1);
    noise(:, 4) = floor(noiseTime);
    noise(:, 5) = round((noiseTime - noise(:, 4)) * 1e9);

    eventArray = [eventArray; noise];
    baselineLabels = [baselineLabels; zeros(noiseNum, 1)];
    timestamp = eventArray(:, 4) + eventArray(:, 5) / 1e9;
    [~, order] = sort(timestamp);
    eventArray = eventArray(order, :);
    baselineLabels = baselineLabels(order);
end

function [eHeight, eWidth] = obtainSensorSize(loaded, data)
    if isfield(loaded, 'cam') && numel(loaded.cam) >= 2
        eHeight = double(loaded.cam{1});
        eWidth = double(loaded.cam{2});
    elseif ~isempty(data) && ~isempty(data(1).Image)
        eHeight = size(data(1).Image, 1);
        eWidth = size(data(1).Image, 2);
    else
        eWidth = max(data(1).events(:, 1)) + 1;
        eHeight = max(data(1).events(:, 2)) + 1;
    end
end

function datasetFile = resolveDatasetFile(datasetFile, codeRoot)
    datasetFile = char(datasetFile);
    if ~isfile(datasetFile)
        datasetFile = fullfile(codeRoot, datasetFile);
    end
    if ~isfile(datasetFile)
        error('Dataset file not found: %s', datasetFile);
    end
end

function config = mergeConfiguration(defaults, supplied)
    config = defaults;
    names = fieldnames(supplied);
    for i = 1:numel(names)
        name = names{i};
        if isfield(config, name) && isstruct(config.(name)) && isstruct(supplied.(name))
            config.(name) = mergeConfiguration(config.(name), supplied.(name));
        else
            config.(name) = supplied.(name);
        end
    end
end

function row = emptyDetailRow()
    row = struct('Dataset', "", 'Packet', 0, 'Experiment', "", ...
        'Category', "", 'Parameter', "", 'Value', NaN, 'Repeat', 0, ...
        'EventCount', 0, 'LineCount', 0, 'ClusterCount', 0, ...
        'Coverage', NaN, 'Precision', NaN, 'F1', NaN, 'IoU', NaN, ...
        'Fragmentation', NaN, 'MergeError', NaN, ...
        'ExtraEventRatio', NaN, 'RuntimeSeconds', NaN);
end

function summary = summarizeResults(detail)
    if isempty(detail)
        summary = table();
        return;
    end
    valueKey = string(detail.Value);
    valueKey(isnan(detail.Value)) = "NA";
    keys = detail.Dataset + "|" + detail.Experiment + "|" + detail.Category + ...
        "|" + detail.Parameter + "|" + valueKey;
    [uniqueKeys, firstIdx, groupIdx] = unique(keys, 'stable');
    summaryRows = repmat(struct('Dataset', "", 'Experiment', "", ...
        'Category', "", 'Parameter', "", 'Value', NaN, 'Runs', 0, ...
        'Packets', 0, 'EventCount', NaN, 'LineCount', NaN, ...
        'ClusterCount', NaN, 'Coverage', NaN, 'Precision', NaN, ...
        'F1', NaN, 'IoU', NaN, 'Fragmentation', NaN, ...
        'FragmentationN', 0, 'MergeError', NaN, 'MergeErrorN', 0, ...
        'ExtraEventRatio', NaN, 'RuntimeSeconds', NaN, ...
        'RuntimeStd', NaN), numel(uniqueKeys), 1);
    for i = 1:numel(uniqueKeys)
        idx = groupIdx == i;
        source = firstIdx(i);
        summaryRows(i).Dataset = detail.Dataset(source);
        summaryRows(i).Experiment = detail.Experiment(source);
        summaryRows(i).Category = detail.Category(source);
        summaryRows(i).Parameter = detail.Parameter(source);
        summaryRows(i).Value = detail.Value(source);
        summaryRows(i).Runs = sum(idx);
        summaryRows(i).Packets = numel(unique(detail.Packet(idx)));
        summaryRows(i).EventCount = finiteMean(detail.EventCount(idx));
        summaryRows(i).LineCount = finiteMean(detail.LineCount(idx));
        summaryRows(i).ClusterCount = finiteMean(detail.ClusterCount(idx));
        summaryRows(i).Coverage = finiteMean(detail.Coverage(idx));
        summaryRows(i).Precision = finiteMean(detail.Precision(idx));
        summaryRows(i).F1 = finiteMean(detail.F1(idx));
        summaryRows(i).IoU = finiteMean(detail.IoU(idx));
        summaryRows(i).Fragmentation = finiteMean(detail.Fragmentation(idx));
        summaryRows(i).FragmentationN = sum(isfinite(detail.Fragmentation(idx)));
        summaryRows(i).MergeError = finiteMean(detail.MergeError(idx));
        summaryRows(i).MergeErrorN = sum(isfinite(detail.MergeError(idx)));
        summaryRows(i).ExtraEventRatio = finiteMean(detail.ExtraEventRatio(idx));
        summaryRows(i).RuntimeSeconds = finiteMean(detail.RuntimeSeconds(idx));
        runtime = detail.RuntimeSeconds(idx);
        runtime = runtime(isfinite(runtime));
        if numel(runtime) > 1
            summaryRows(i).RuntimeStd = std(runtime);
        elseif numel(runtime) == 1
            summaryRows(i).RuntimeStd = 0;
        end
    end
    summary = struct2table(summaryRows);
end

function value = finiteMean(values)
    values = values(isfinite(values));
    if isempty(values)
        value = NaN;
    else
        value = mean(values);
    end
end
