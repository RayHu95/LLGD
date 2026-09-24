function prepareHQFBoxes(bagPath, outputPath, frameNum, windowDuration)
    codeRoot = fileparts(fileparts(mfilename('fullpath')));
    if nargin < 1 || isempty(bagPath)
        bagPath = fullfile(codeRoot, 'datasets', 'hqf', 'boxes.bag');
    end
    if nargin < 2 || isempty(outputPath)
        outputPath = fullfile(codeRoot, 'datasets', 'hqf_boxes_events.mat');
    end
    if nargin < 3
        frameNum = 30;
    end
    if nargin < 4
        windowDuration = 0.02;
    end

    addpath(fileparts(mfilename('fullpath')));
    bag = rosbag(bagPath);
    eventSelection = select(bag, 'Topic', '/dvs/events');
    imageSelection = select(bag, 'Topic', '/dvs/image_raw');
    if eventSelection.NumMessages == 0 || imageSelection.NumMessages < frameNum+2
        error('The HQF bag does not contain enough event or image messages.');
    end
    eventMessages = readMessages(eventSelection, 1, 'DataFormat', 'struct');
    eventMessage = eventMessages{1};
    if eventMessage.Height ~= 180 || eventMessage.Width ~= 240
        error('The HQF event sensor is not 240 by 180 pixels.');
    end

    frameIdx = round(linspace(10, imageSelection.NumMessages-2, frameNum));
    data = repmat(struct('Image', [], 'qR', [], 't', [], ...
        'eventsNum', 0, 'events', []), 1, frameNum);
    frameTime = zeros(frameNum, 1);
    packetDuration = zeros(frameNum, 1);
    startOffset = zeros(frameNum, 1);
    endOffset = zeros(frameNum, 1);

    for i = 1:frameNum
        imageMessages = readMessages(imageSelection, frameIdx(i), ...
            'DataFormat', 'struct');
        imageMessage = imageMessages{1};
        if ~strcmp(imageMessage.Encoding, 'mono8')
            error('Unsupported HQF image encoding: %s.', imageMessage.Encoding);
        end
        frameTime(i) = stampToSeconds(imageMessage.Header.Stamp);
        image = reshape(uint8(imageMessage.Data), ...
            [double(imageMessage.Step), double(imageMessage.Height)])';
        image = image(:, 1:double(imageMessage.Width));

        timeStart = frameTime(i);
        timeEnd = timeStart + windowDuration;
        selectionStart = max(bag.StartTime, timeStart-0.05);
        selectionEnd = min(bag.EndTime, timeEnd+0.05);
        packetSelection = select(bag, 'Time', [selectionStart, selectionEnd], ...
            'Topic', '/dvs/events');
        eventMessages = readMessages(packetSelection, 'DataFormat', 'struct');
        eventArray = collectEvents(eventMessages, timeStart, timeEnd);
        if isempty(eventArray)
            error('No events were found for frame %d.', frameIdx(i));
        end

        timestamp = eventArray(:,4) + eventArray(:,5)/1e9;
        packetDuration(i) = max(timestamp)-min(timestamp);
        startOffset(i) = min(timestamp)-timeStart;
        endOffset(i) = max(timestamp)-timeStart;
        data(i).Image = image;
        data(i).events = eventArray;
        data(i).eventsNum = size(eventArray, 1);
    end

    eHeight = size(data(1).Image, 1);
    eWidth = size(data(1).Image, 2);
    cam = {eHeight, eWidth, [], []};
    source = struct('dataset', 'High Quality Frames', ...
        'sequence', 'boxes', 'windowDuration', windowDuration, ...
        'windowReference', 'after frame timestamp', ...
        'bagPath', 'datasets/hqf/boxes.bag', 'bagStartTime', bag.StartTime, ...
        'bagEndTime', bag.EndTime, ...
        'eventMessages', eventSelection.NumMessages, ...
        'imageMessages', imageSelection.NumMessages, ...
        'sensorHeight', double(eventMessage.Height), ...
        'sensorWidth', double(eventMessage.Width));

    eventCount = [data.eventsNum]';
    save(outputPath, 'cam', 'data', 'frameIdx', 'frameTime', ...
        'startOffset', 'endOffset', 'packetDuration', 'source', '-v7.3');

    fprintf('Saved %s with %d event arrays.\n', outputPath, frameNum);
    fprintf('Events per packet: min %d, mean %.1f, max %d.\n', ...
        min(eventCount), mean(eventCount), max(eventCount));
end

function eventArray = collectEvents(messages, timeStart, timeEnd)
    eventArray = zeros(0, 5);
    for i = 1:numel(messages)
        events = messages{i}.Events;
        if isempty(events)
            continue;
        end
        stamps = [events.Ts];
        sec = double([stamps.Sec])';
        nsec = double([stamps.Nsec])';
        timestamp = sec + nsec/1e9;
        keep = timestamp >= timeStart & timestamp < timeEnd;
        if any(keep)
            x = double([events.X])';
            y = double([events.Y])';
            polarity = double([events.Polarity])';
            eventArray = [eventArray; x(keep), y(keep), polarity(keep), ...
                sec(keep), nsec(keep)]; %#ok<AGROW>
        end
    end
    if ~isempty(eventArray)
        [~, order] = sort(eventArray(:,4)+eventArray(:,5)/1e9);
        eventArray = eventArray(order, :);
    end
end

function timestamp = stampToSeconds(stamp)
    timestamp = double(stamp.Sec) + double(stamp.Nsec)/1e9;
end
