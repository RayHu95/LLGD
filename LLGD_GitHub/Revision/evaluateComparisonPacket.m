function [labels, runtime] = evaluateComparisonPacket(method, eventArray, ...
        eWidth, eHeight, timeOrigin, config)
    switch char(method)
        case 'LLGD'
            [labels, runtime] = runLLGD(eventArray, eWidth, eHeight, ...
                timeOrigin, config.detectorParameters);
        case 'ST'
            [labels, runtime] = runST(eventArray, eWidth, eHeight, timeOrigin);
        case 'ELiSeD'
            [labels, runtime] = runELiSeD(eventArray, eHeight, eWidth, ...
                timeOrigin, config.ELiSeDBufferSize, ...
                config.ELiSeDTimestampCutoff);
        case 'LE-calib'
            [labels, runtime] = runLEcalib(eventArray, eWidth, eHeight, ...
                timeOrigin, config.LETimeScale);
        otherwise
            error('Unknown comparison method: %s', char(method));
    end
end

function [labels, runtime] = runLLGD(eventArray, eWidth, eHeight, timeOrigin, parameters)
    tic;
    timestamp = eventArray(:, 4) + eventArray(:, 5) / 1e9;
    detector = EventLineDBSCAN();
    detector.pointData = [eventArray(:, 1) / double(eWidth), ...
        eventArray(:, 2) / double(eHeight), timestamp - timeOrigin];
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

function [labels, runtime] = runST(eventArray, eWidth, eHeight, timeOrigin)
    tic;
    timestamp = eventArray(:, 4) + eventArray(:, 5) / 1e9;
    events = [eventArray(:, 1:2), timestamp - timeOrigin];
    detectedLines = ST_method(events, eHeight, eWidth);
    labels = zeros(size(eventArray, 1), 1);
    for i = 1:numel(detectedLines)
        labels(detectedLines{i}.idx) = i;
    end
    runtime = toc;
end

function [labels, runtime] = runELiSeD(eventArray, eHeight, eWidth, timeOrigin, ...
        bufferSize, timestampCutoff)
    tic;
    timestamp = eventArray(:, 4) + eventArray(:, 5) / 1e9;
    events = [eventArray(:, 1) + 1, eventArray(:, 2) + 1, ...
        timestamp - timeOrigin, eventArray(:, 3)];
    detector = ELiSeDDetector('SensorSize', [eHeight, eWidth], ...
        'BufferSize', bufferSize, 'TimestampCutoff', timestampCutoff);
    segments = detector.processEvents(events);
    labels = zeros(size(eventArray, 1), 1);
    recent = timestamp > max(timestamp) - timestampCutoff;
    eventPixels = round(events(:, 1:2));
    for i = 1:numel(segments)
        inRegion = ismember(eventPixels, round(segments{i}.pixels), 'rows');
        labels(recent & inRegion & labels == 0) = i;
    end
    runtime = toc;
end

function [labels, runtime] = runLEcalib(eventArray, eWidth, eHeight, timeOrigin, timeScale)
    tic;
    timestamp = eventArray(:, 4) + eventArray(:, 5) / 1e9;
    pointData = [eventArray(:, 1)' / double(eWidth); ...
        eventArray(:, 2)' / double(eHeight); ...
        ((timestamp - timeOrigin) / timeScale)'];
    detector = LineDetection3D();
    detector.pointData = pointData;
    detector.pointNum = size(pointData, 2);
    detector.k = 30;
    regions = detector.pointCloudSegmentation();
    labels = zeros(size(eventArray, 1), 1);
    for i = 1:numel(regions)
        labels(regions{i}) = i;
    end
    runtime = toc;
end
