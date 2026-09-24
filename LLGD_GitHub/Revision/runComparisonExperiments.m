function [summary, detail, config] = runComparisonExperiments(datasetFiles, config)
    codeRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(genpath(fullfile(codeRoot, 'LineDetection')));
    addpath(genpath(fullfile(codeRoot, 'ST')));
    addpath(genpath(fullfile(codeRoot, 'ELiSed')));
    addpath(genpath(fullfile(codeRoot, 'LEcalib')));
    addpath(genpath(fullfile(codeRoot, 'frameGT')));
    addpath(fileparts(mfilename('fullpath')));

    if nargin < 1 || isempty(datasetFiles)
        datasetFiles = {fullfile(codeRoot, 'datasets', 'shapes_6dof_events.mat'), ...
            fullfile(codeRoot, 'datasets', 'urban_events.mat'), ...
            fullfile(codeRoot, 'datasets', 'office_spiral_events.mat'), ...
            fullfile(codeRoot, 'datasets', 'hqf_boxes_events.mat')};
    elseif ischar(datasetFiles) || isstring(datasetFiles)
        datasetFiles = cellstr(datasetFiles);
    end
    defaults = defaultConfiguration(codeRoot);
    if nargin < 2 || isempty(config)
        config = defaults;
    else
        config = mergeConfiguration(defaults, config);
    end
    rng(config.seed, 'twister');

    methods = {'LLGD', 'ST', 'ELiSeD', 'LE-calib'};
    rows = repmat(emptyDetailRow(), 0, 1);
    rowNum = 0;
    for datasetIdx = 1:numel(datasetFiles)
        datasetFile = resolveDatasetFile(datasetFiles{datasetIdx}, codeRoot);
        loaded = load(datasetFile);
        data = loaded.data;
        [eHeight, eWidth] = obtainSensorSize(loaded, data);
        packetNum = min(numel(data), config.maxPackets);
        baseline = buildFrameBaseline(data(1:packetNum));
        timeOrigin = firstTimestamp(data);
        for warmupIdx = 1:config.runtimeWarmup
            warmupEvents = double(data(1).events);
            for methodIdx = 1:numel(methods)
                evaluateComparisonPacket(methods{methodIdx}, warmupEvents, ...
                    eWidth, eHeight, timeOrigin, config);
            end
        end
        [~, datasetName] = fileparts(datasetFile);
        fprintf('\n[%s] %d event arrays\n', datasetName, packetNum);

        for packetIdx = 1:packetNum
            eventArray = double(data(packetIdx).events);
            for methodIdx = 1:numel(methods)
                rng(config.seed + 100000 + packetIdx * 1000 + 1, 'twister');
                [labels, runtime] = evaluateComparisonPacket(methods{methodIdx}, ...
                    eventArray, eWidth, eHeight, timeOrigin, config);
                metrics = evaluateEventLabels(baseline(packetIdx).labels, labels);

                rowNum = rowNum + 1;
                rows(rowNum, 1) = emptyDetailRow();
                rows(rowNum).Dataset = string(datasetName);
                rows(rowNum).Packet = packetIdx;
                rows(rowNum).Method = string(methods{methodIdx});
                rows(rowNum).EventCount = size(eventArray, 1);
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

    detail = struct2table(rows);
    summary = summarizeResults(detail);
    if ~isfolder(config.outputFolder)
        mkdir(config.outputFolder);
    end
    writetable(detail, fullfile(config.outputFolder, [config.resultPrefix, '_detail.csv']));
    writetable(summary, fullfile(config.outputFolder, [config.resultPrefix, '_summary.csv']));
    save(fullfile(config.outputFolder, [config.resultPrefix, '_results.mat']), ...
        'summary', 'detail', 'config', 'datasetFiles', '-v7.3');
    fprintf('\nSaved comparison results to %s\n', config.outputFolder);
end

function config = defaultConfiguration(codeRoot)
    config.seed = 2025;
    config.maxPackets = 30;
    config.outputFolder = fullfile(codeRoot, 'Revision', 'results');
    config.resultPrefix = 'comparison';
    config.runtimeWarmup = 1;
    config.ELiSeDBufferSize = 5000;
    config.ELiSeDTimestampCutoff = 0.03;
    config.LETimeScale = 0.1;
    config.detectorParameters = struct('MADThreshold', 3.5, ...
        'PinThreshold', 0.8, 'PwThreshold', 0.8, ...
        'OverlapThreshold', 0.8, 'Eps1', 0.02, 'Eps2', 0.02, ...
        'UseWeights', true, 'UseVerification', true, ...
        'UseGlobalExpansion', true);
end

function timestamp = firstTimestamp(data)
    timestamp = 0;
    for i = 1:numel(data)
        if ~isempty(data(i).events)
            timestamp = double(data(i).events(1, 4)) + ...
                double(data(i).events(1, 5)) / 1e9;
            return;
        end
    end
end

function [eHeight, eWidth] = obtainSensorSize(loaded, data)
    if isfield(loaded, 'cam') && numel(loaded.cam) >= 2
        eHeight = double(loaded.cam{1});
        eWidth = double(loaded.cam{2});
    else
        eHeight = size(data(1).Image, 1);
        eWidth = size(data(1).Image, 2);
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
    row = struct('Dataset', "", 'Packet', 0, 'Method', "", ...
        'EventCount', 0, 'LineCount', 0, 'ClusterCount', 0, ...
        'Coverage', NaN, 'Precision', NaN, 'F1', NaN, 'IoU', NaN, ...
        'Fragmentation', NaN, 'MergeError', NaN, ...
        'ExtraEventRatio', NaN, 'RuntimeSeconds', NaN);
end

function summary = summarizeResults(detail)
    keys = detail.Dataset + "|" + detail.Method;
    [uniqueKeys, firstIdx, groupIdx] = unique(keys, 'stable');
    rows = repmat(struct('Dataset', "", 'Method', "", 'Packets', 0, ...
        'EventCount', NaN, 'LineCount', NaN, 'ClusterCount', NaN, ...
        'Coverage', NaN, 'Precision', NaN, 'F1', NaN, 'IoU', NaN, ...
        'Fragmentation', NaN, 'FragmentationN', 0, ...
        'MergeError', NaN, 'MergeErrorN', 0, 'ExtraEventRatio', NaN, ...
        'RuntimeSeconds', NaN, 'RuntimeStd', NaN), numel(uniqueKeys), 1);
    for i = 1:numel(uniqueKeys)
        idx = groupIdx == i;
        source = firstIdx(i);
        rows(i).Dataset = detail.Dataset(source);
        rows(i).Method = detail.Method(source);
        rows(i).Packets = sum(idx);
        rows(i).FragmentationN = sum(isfinite(detail.Fragmentation(idx)));
        rows(i).MergeErrorN = sum(isfinite(detail.MergeError(idx)));
        names = {'EventCount', 'LineCount', 'ClusterCount', 'Coverage', ...
            'Precision', 'F1', 'IoU', 'Fragmentation', 'MergeError', ...
            'ExtraEventRatio', 'RuntimeSeconds'};
        for j = 1:numel(names)
            values = detail.(names{j})(idx);
            values = values(isfinite(values));
            if ~isempty(values)
                rows(i).(names{j}) = mean(values);
            end
        end
        runtime = detail.RuntimeSeconds(idx);
        runtime = runtime(isfinite(runtime));
        if numel(runtime) > 1
            rows(i).RuntimeStd = std(runtime);
        elseif numel(runtime) == 1
            rows(i).RuntimeStd = 0;
        end
    end
    summary = struct2table(rows);
end
