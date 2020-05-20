# Run benchmark for measurement
# Please install PyTorch (see https://pytorch.org/) before running this benchmark. Like the following:
# GPU:   conda install pytorch torchvision cudatoolkit=10.1 -c pytorch
# CPU:   conda install pytorch torchvision cpuonly -c pytorch

# When run_cli=true, this script is self-contained and you need not copy other files to run benchmarks
#                    it will use onnxruntime-tools package.
# If run_cli=false, it depends on other python script (*.py) files in this directory.
run_cli=true

# only need once
run_install=false

# Engines to test.
run_ort=true
run_torch=false
run_torchscript=true

# Devices to test (You can run either CPU or GPU, but not both: gpu need onnxruntime-gpu, and CPU need onnxruntime).
run_gpu_fp32=true
run_gpu_fp16=true
run_cpu=false

average_over=1000
# CPU takes longer time to run, only run 100 inferences to get average latency.
if [ "$run_cpu" = true ] ; then
  average_over=100
fi

# enable optimizer (use script instead of OnnxRuntime for graph optimization)
use_optimizer=true

# Batch Sizes and Sequence Lengths
batch_sizes="1 4"
sequence_lengths="8 16 32 64 128 256 512 1024"

# Pretrained transformers models can be a subset of: bert-base-cased roberta-base gpt2 distilgpt2 distilbert-base-uncased
models_to_test="bert-base-cased roberta-base gpt2"

# If you have mutliple GPUs, you can choose one GPU for test. Here is an example to use the second GPU:
# export CUDA_VISIBLE_DEVICES=1

#This script will generate a logs file with a list of commands used in tests.
set log_file=benchmark.log
echo echo ort=$run_ort torch=$run_torch torchscript=$run_torchscript gpu_fp32=$run_gpu_fp32 gpu_fp16=$run_gpu_fp16 cpu=$run_cpu optimizer=$use_optimizer batch=$batch_sizes sequence=$sequence_length models=$models_to_test >> $log_file

#Set it to false to skip testing. You can use it to dry run this script with the log file.
run_tests=true
# -------------------------------------------
if [ "$run_install" = true ] ; then
  if [ "$run_cpu" = true ] ; then
    pip install --upgrade onnxruntime
  else
    pip install --upgrade onnxruntime-gpu
  fi
  pip install --upgrade onnxruntime-tools
  pip install --upgrade git+https://github.com/huggingface/transformers
fi

if [ "$run_cli" = true ] ; then
  echo "Use onnxruntime_tools.transformers.benchmark" 
  optimizer_script="-m onnxruntime_tools.transformers.benchmark"
else
  optimizer_script="benchmark.py"
fi

onnx_export_options="-v -b 0 --overwrite -f fusion.csv"
benchmark_options="-b $batch_sizes -s sequence_lengths -t $average_over -f fusion.csv -r result.csv -d detail.csv"

if [ "$use_optimizer" = true ] ; then
  onnx_export_options="$onnx_export_options -o"
  benchmark_options="$benchmark_options -o"
fi

# -------------------------------------------
run_on_test() {
    if [ "$run_ort" = true ] ; then
      echo python $optimizer_script -m $1 $onnx_export_options $2 $3 >> $log_file
      echo python $optimizer_script -m $1 $benchmark_options $2 $3 >> $log_file
      if [ "run_tests" = true ] ; then
        python $optimizer_script -m $1 $onnx_export_options $2 $3
        python $optimizer_script -m $1 $benchmark_options $2 $3
      fi
    fi

    if [ "$run_torch" = true ] ; then
      echo python $optimizer_script -e torch -m $1 $benchmark_options $2 $3 >> $log_file
      if [ "run_tests" = true ] ; then
        python $optimizer_script -e torch -m $1 $benchmark_options $2 $3
      fi
    fi

    if [ "$run_torchscript" = true ] ; then
      echo python $optimizer_script -e torchscript -m $1 $benchmark_options $2 $3 >> $log_file
      if [ "run_tests" = true ] ; then
        python $optimizer_script -e torchscript -m $1 $benchmark_options $2 $3
      fi
    fi
}

# -------------------------------------------
if [ "$run_gpu_fp32" = true ] ; then
  for m in $models_to_test
  do
    echo Run GPU FP32 Benchmark on model ${m}
    run_on_test "${m}" -g
  done
fi

if [ "$run_gpu_fp16" = true ] ; then
  for m in $models_to_test
  do
    echo Run GPU FP16 Benchmark on model ${m}
    run_on_test "${m}" -g --fp16
  done
fi

if [ "$run_cpu" = true ] ; then
  for m in $models_to_test
  do
    echo Run CPU Benchmark on model ${m}
    run_on_test "${m}" 
  done
fi 

echo log file: $log_file

# Remove duplicated lines
awk '!x[$0]++' ./result.csv > summary_result.csv
awk '!x[$0]++' ./fusion.csv > summary_fusion.csv
awk '!x[$0]++' ./detail.csv > summary_detail.csv