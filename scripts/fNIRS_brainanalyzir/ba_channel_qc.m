% SYNTAX:
% qc = ba_channel_qc(raw, channels, qcParams)
%
%
% DESCRIPTION:
% Channel quality on RAW INTENSITY at the native sampling rate (before
% resampling, because the cardiac band 0.5-2.5 Hz needs fs > 5 Hz).
%
% QT-NIRS style (Hernandez & Pollonini, 2020; as in the CICI pipeline):
%   1. band-pass both wavelengths to the cardiac band (QC only; the analysis
%      signal is never filtered);
%   2. split into window_sec windows and, per window,
%        SCI = zero-lag correlation of the two normalized wavelengths
%        PSP = peak power of their cross-correlation spectrum;
%   3. a window is good if SCI >= sci_threshold AND PSP >= psp_threshold;
%   4. QualityFraction = proportion of good windows; channel passes when
%      QualityFraction >= quality_threshold.
% Saturation/dropout: channel flagged if any wavelength has non-finite or
% non-positive intensity in more than 1% of samples.
%
%
% INPUTS:
% raw      - nirs.core.Data (raw intensity), trimmed.
% channels - table from ba_load_subject (Label, Source, Detector, Cols, IsShort).
% qcParams - params.qc.
%
%
% OUTPUTS:
% qc - table, one row per channel: Label, IsShort, SCI_mean, PSP_mean,
%      QualityFraction, PassQuality, Saturated.
function qc = ba_channel_qc(raw, channels, qcParams)

fs = raw.Fs;
assert(fs > 2 * qcParams.cardiac_band(2), ...
    'Sampling rate %.3g Hz is too low for the cardiac QC band.', fs);
[b, a] = butter(3, qcParams.cardiac_band / (fs/2), 'bandpass');
winLen = round(qcParams.window_sec * fs);

nCh = height(channels);
SCI_mean = nan(nCh,1);
PSP_mean = nan(nCh,1);
QualityFraction = nan(nCh,1);
Saturated = false(nCh,1);

for c = 1:nCh
    x = raw.data(:, channels.Cols{c});
    bad = ~isfinite(x) | x <= 0;
    Saturated(c) = any(mean(bad, 1) > 0.01);
    if Saturated(c) && any(all(bad, 1))
        QualityFraction(c) = 0;
        continue
    end
    x = fillmissing(x, 'linear');
    x(x <= 0) = eps;
    xf = filtfilt(b, a, x);

    nWin = floor(size(xf,1) / winLen);
    sciW = nan(nWin,1);
    pspW = nan(nWin,1);
    for w = 1:nWin
        seg = xf((w-1)*winLen + (1:winLen), :);
        seg = (seg - mean(seg)) ./ std(seg);
        if any(~isfinite(seg(:)))
            continue
        end
        sciW(w) = mean(seg(:,1) .* seg(:,2)) * winLen / (winLen - 1);
        cc = xcorr(seg(:,1), seg(:,2), 'unbiased');
        [pxx, f] = periodogram(cc, hamming(numel(cc)), numel(cc), fs, 'power');
        inBand = f >= qcParams.cardiac_band(1) & f <= qcParams.cardiac_band(2);
        pspW(w) = max(pxx(inBand));
    end
    good = sciW >= qcParams.sci_threshold & pspW >= qcParams.psp_threshold;
    SCI_mean(c) = mean(sciW, 'omitnan');
    PSP_mean(c) = mean(pspW, 'omitnan');
    QualityFraction(c) = mean(good);
end

PassQuality = QualityFraction >= qcParams.quality_threshold & ~Saturated;
qc = table(channels.Label, channels.IsShort, SCI_mean, PSP_mean, ...
    QualityFraction, PassQuality, Saturated, ...
    'VariableNames', {'Label', 'IsShort', 'SCI_mean', 'PSP_mean', ...
    'QualityFraction', 'PassQuality', 'Saturated'});
end
