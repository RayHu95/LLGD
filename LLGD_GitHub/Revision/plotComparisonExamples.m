function metrics = plotComparisonExamples(config)
    codeRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(genpath(fullfile(codeRoot, 'LineDetection')));
    addpath(genpath(fullfile(codeRoot, 'ST')));
    addpath(genpath(fullfile(codeRoot, 'ELiSed')));
    addpath(genpath(fullfile(codeRoot, 'LEcalib')));
    addpath(genpath(fullfile(codeRoot, 'frameGT')));
    addpath(fileparts(mfilename('fullpath')));

    defaults = defaultConfiguration(codeRoot);
    if nargin < 1 || isempty(config)
        config = defaults;
    else
        config = mergeConfiguration(defaults, config);
    end

    loaded = load(config.datasetFile);
    data = loaded.data;
    [eHeight, eWidth] = obtainSensorSize(loaded, data);
    timeOrigin = firstTimestamp(data);
    [baseline, ~] = buildFrameBaseline(data(config.packetIds));
    methods = {'ST', 'ELiSeD', 'LE-calib', 'LLGD'};
    names = {'Frame reference', 'Everding et al.$^\dagger$', ...
        'ELiSeD$^\dagger$', 'LEcalib RG$^\dagger$', 'LLGD'};
    panelLabels = cell(numel(config.packetIds), numel(names));
    metricRows = repmat(struct('Packet', 0, 'Method', "", ...
        'F1', NaN, 'ClusterCount', 0), 0, 1);
    rowNum = 0;

    for packetRow = 1:numel(config.packetIds)
        packetIdx = config.packetIds(packetRow);
        eventArray = double(data(packetIdx).events);
        panelLabels{packetRow, 1} = baseline(packetRow).labels;
        for methodIdx = 1:numel(methods)
            rng(config.seed + 100000 + packetIdx * 1000 + 1, 'twister');
            [labels, ~] = evaluateComparisonPacket(methods{methodIdx}, ...
                eventArray, eWidth, eHeight, timeOrigin, config);
            current = evaluateEventLabels(baseline(packetRow).labels, labels);
            panelLabels{packetRow, methodIdx + 1} = labels;
            rowNum = rowNum + 1;
            metricRows(rowNum, 1).Packet = packetIdx;
            metricRows(rowNum).Method = string(methods{methodIdx});
            metricRows(rowNum).F1 = current.F1;
            metricRows(rowNum).ClusterCount = current.clusterCount;
        end
    end

    metrics = struct2table(metricRows);
    drawComparison(data(config.packetIds), panelLabels, names, ...
        eWidth, eHeight, config);
    writetable(metrics, fullfile(config.outputFolder, ...
        [config.outputName, '_metrics.csv']));
end

function config = defaultConfiguration(codeRoot)
    config.seed = 2025;
    config.packetIds = [9, 24];
    config.datasetFile = fullfile(codeRoot, 'datasets', ...
        'shapes_6dof_events.mat');
    config.outputFolder = fullfile(codeRoot, 'Revision', 'results');
    config.outputName = 'comparison_examples';
    config.ELiSeDBufferSize = 5000;
    config.ELiSeDTimestampCutoff = 0.03;
    config.LETimeScale = 0.1;
    config.detectorParameters = struct('MADThreshold', 3.5, ...
        'PinThreshold', 0.8, 'PwThreshold', 0.8, ...
        'OverlapThreshold', 0.8, 'Eps1', 0.02, 'Eps2', 0.02, ...
        'UseWeights', true, 'UseVerification', true, ...
        'UseGlobalExpansion', true);
end

function drawComparison(data, panelLabels, names, eWidth, eHeight, config)
    figureHandle = figure('Color', 'w', 'Position', [40, 60, 1580, 610]);
    panelLetter = 'abcdefghij';
    for row = 1:size(panelLabels, 1)
        eventArray = double(data(row).events);
        for col = 1:size(panelLabels, 2)
            subplot(2, 5, (row - 1) * 5 + col);
            labels = panelLabels{row, col};
            scatter(eventArray(:, 1), eventArray(:, 2), 3, ...
                [0.80, 0.80, 0.80], 'filled');
            hold on;
            clusterIds = unique(labels(labels > 0));
            colors = hsv(max(1, numel(clusterIds)));
            for i = 1:numel(clusterIds)
                idx = labels == clusterIds(i);
                scatter(eventArray(idx, 1), eventArray(idx, 2), 5, ...
                    colors(i, :), 'filled');
            end
            formatEventAxes(eWidth, eHeight);
            panelIdx = (row - 1) * 5 + col;
            title(sprintf('(%c) %s, packet %d', panelLetter(panelIdx), ...
                names{col}, config.packetIds(row)), ...
                'Interpreter', 'latex');
        end
    end
    set(findall(figureHandle, 'Type', 'axes'), 'FontName', ...
        'Times New Roman', 'FontSize', 8, 'LineWidth', 0.8);
    if ~isfolder(config.outputFolder)
        mkdir(config.outputFolder);
    end
    set(figureHandle, 'PaperPositionMode', 'auto');
    print(figureHandle, fullfile(config.outputFolder, ...
        [config.outputName, '.png']), '-dpng', '-r300');
    print(figureHandle, fullfile(config.outputFolder, ...
        [config.outputName, '.eps']), '-depsc2', '-painters');
end

function formatEventAxes(eWidth, eHeight)
    axis([0, eWidth, 0, eHeight]);
    axis equal;
    set(gca, 'YDir', 'reverse', 'Color', 'w');
    box on;
    xlabel('x');
    ylabel('y');
end

function timestamp = firstTimestamp(data)
    timestamp = double(data(1).events(1, 4)) + ...
        double(data(1).events(1, 5)) / 1e9;
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
