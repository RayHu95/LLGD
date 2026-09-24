function [selectedPackets, scanMetrics] = plotRevisionExamples(config)
    codeRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(genpath(fullfile(codeRoot, 'LineDetection')));
    addpath(genpath(fullfile(codeRoot, 'frameGT')));
    addpath(fileparts(mfilename('fullpath')));

    defaults = defaultConfiguration(codeRoot);
    if nargin < 1 || isempty(config)
        config = defaults;
    else
        config = mergeConfiguration(defaults, config);
    end
    rng(config.seed, 'twister');

    datasetFiles = {fullfile(codeRoot, 'datasets', 'urban_events.mat'), ...
        fullfile(codeRoot, 'datasets', 'office_spiral_events.mat')};
    datasetKeys = ["urban_events", "office_spiral_events"];
    datasetTitles = {'Urban', 'Office spiral'};
    selectedRows = repmat(struct('Dataset', "", 'Packet', 0, ...
        'F1', NaN, 'MedianF1', NaN), 2, 1);
    panelData = cell(2, 1);
    detail = readtable(config.comparisonDetailFile);
    keep = string(detail.Method) == "LLGD" & ...
        ismember(string(detail.Dataset), datasetKeys);
    scanMetrics = detail(keep, {'Dataset', 'Packet', 'F1', ...
        'LineCount', 'ClusterCount'});

    for datasetIdx = 1:2
        loaded = load(datasetFiles{datasetIdx});
        data = loaded.data;
        [eHeight, eWidth] = obtainSensorSize(loaded, data);
        currentRows = scanMetrics(string(scanMetrics.Dataset) == ...
            datasetKeys(datasetIdx), :);
        currentRows = sortrows(currentRows, 'Packet');
        packetIds = currentRows.Packet;
        f1 = currentRows.F1;
        if ~isempty(config.candidatePackets)
            keep = ismember(packetIds, config.candidatePackets);
            packetIds = packetIds(keep);
            f1 = f1(keep);
        end
        timeOrigin = firstTimestamp(data);

        valid = find(isfinite(f1));
        if isempty(valid)
            error('No finite LLGD F1 value is available for %s.', datasetTitles{datasetIdx});
        end
        medianF1 = median(f1(valid));
        [~, nearest] = min(abs(f1(valid) - medianF1));
        selectedLocal = valid(nearest);
        selectedPacket = packetIds(selectedLocal);
        [~, lineSets] = buildFrameBaseline(data(selectedPacket));
        eventArray = double(data(selectedPacket).events);
        rng(config.seed + 100000 + selectedPacket * 1000 + 1, 'twister');
        [labels, ~] = evaluateComparisonPacket('LLGD', eventArray, ...
            eWidth, eHeight, timeOrigin, config);
        selectedRows(datasetIdx).Dataset = string(datasetTitles{datasetIdx});
        selectedRows(datasetIdx).Packet = selectedPacket;
        selectedRows(datasetIdx).F1 = f1(selectedLocal);
        selectedRows(datasetIdx).MedianF1 = medianF1;
        panelData{datasetIdx} = struct('Image', data(selectedPacket).Image, ...
            'Events', eventArray, 'Lines', lineSets{1}, 'Labels', labels, ...
            'Width', eWidth, 'Height', eHeight, ...
            'Title', datasetTitles{datasetIdx}, 'Packet', selectedPacket, ...
            'F1', f1(selectedLocal));
    end

    selectedPackets = struct2table(selectedRows);
    drawExamples(panelData, config);
    writetable(selectedPackets, fullfile(config.outputFolder, ...
        [config.outputName, '_packets.csv']));
end

function config = defaultConfiguration(codeRoot)
    config.seed = 2025;
    config.candidatePackets = [];
    config.timeWindow = 0.020;
    config.outputFolder = fullfile(codeRoot, 'Revision', 'results');
    config.outputName = 'real_scene_examples';
    config.comparisonDetailFile = fullfile(config.outputFolder, ...
        'comparison_four_detail.csv');
    config.ELiSeDBufferSize = 5000;
    config.ELiSeDTimestampCutoff = 0.03;
    config.LETimeScale = 0.1;
    config.detectorParameters = struct('MADThreshold', 3.5, ...
        'PinThreshold', 0.8, 'PwThreshold', 0.8, ...
        'OverlapThreshold', 0.8, 'Eps1', 0.02, 'Eps2', 0.02, ...
        'UseWeights', true, 'UseVerification', true, ...
        'UseGlobalExpansion', true);
end

function drawExamples(panelData, config)
    figureHandle = figure('Color', 'w', 'Position', [80, 80, 1320, 690]);
    panelLetters = {'(a)', '(b)', '(c)'; '(d)', '(e)', '(f)'};
    panelPositions = [0.045, 0.56, 0.28, 0.36; ...
        0.36, 0.56, 0.28, 0.36; 0.675, 0.56, 0.28, 0.36; ...
        0.045, 0.08, 0.28, 0.36; 0.36, 0.08, 0.28, 0.36; ...
        0.675, 0.08, 0.28, 0.36];
    for row = 1:2
        current = panelData{row};
        eventArray = current.Events;
        timestamp = eventArray(:, 4) + eventArray(:, 5) / 1e9;
        windowMask = timestamp >= max(timestamp) - config.timeWindow;

        subplot(2, 3, 3 * row - 2);
        if size(current.Image, 3) == 3
            imshow(rgb2gray(current.Image));
        else
            imshow(current.Image);
        end
        hold on;
        colors = hsv(max(1, numel(current.Lines)));
        for i = 1:numel(current.Lines)
            plot([current.Lines(i).point1(1), current.Lines(i).point2(1)], ...
                [current.Lines(i).point1(2), current.Lines(i).point2(2)], '-', ...
                'Color', colors(i, :), 'LineWidth', 0.8);
        end
        title(sprintf('%s %s: frame reference', panelLetters{row, 1}, current.Title));
        set(gca, 'Position', panelPositions(3 * row - 2, :));

        subplot(2, 3, 3 * row - 1);
        scatter(eventArray(windowMask, 1), eventArray(windowMask, 2), 4, ...
            [0.15, 0.15, 0.15], 'filled');
        formatEventAxes(current.Width, current.Height);
        title(sprintf('%s 20 ms event projection', panelLetters{row, 2}));
        set(gca, 'Position', panelPositions(3 * row - 1, :));

        subplot(2, 3, 3 * row);
        labels = current.Labels;
        noiseMask = windowMask & labels <= 0;
        scatter(eventArray(noiseMask, 1), eventArray(noiseMask, 2), 3, ...
            [0.78, 0.78, 0.78], 'filled');
        hold on;
        clusterIds = unique(labels(windowMask & labels > 0));
        colors = hsv(max(1, numel(clusterIds)));
        for i = 1:numel(clusterIds)
            idx = windowMask & labels == clusterIds(i);
            scatter(eventArray(idx, 1), eventArray(idx, 2), 5, colors(i, :), 'filled');
        end
        formatEventAxes(current.Width, current.Height);
        title(sprintf('%s LLGD, packet %d, F1 = %.3f', ...
            panelLetters{row, 3}, current.Packet, current.F1));
        set(gca, 'Position', panelPositions(3 * row, :));
    end
    set(findall(figureHandle, 'Type', 'axes'), 'FontName', 'Times New Roman', ...
        'FontSize', 9, 'LineWidth', 0.8);
    if ~isfolder(config.outputFolder)
        mkdir(config.outputFolder);
    end
    set(figureHandle, 'PaperPositionMode', 'auto');
    print(figureHandle, fullfile(config.outputFolder, [config.outputName, '.png']), ...
        '-dpng', '-r300');
    print(figureHandle, fullfile(config.outputFolder, [config.outputName, '.eps']), ...
        '-depsc2', '-painters');
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
