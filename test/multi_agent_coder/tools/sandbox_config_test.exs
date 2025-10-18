defmodule MultiAgentCoder.Tools.SandboxConfigTest do
  use ExUnit.Case, async: true

  alias MultiAgentCoder.Tools.SandboxConfig

  describe "new/2" do
    test "creates config with valid working directory" do
      working_dir = System.tmp_dir!()
      {:ok, config} = SandboxConfig.new(working_dir)

      assert config.working_dir == Path.expand(working_dir)
      assert config.allowed_paths == []
      assert config.env_vars == %{}
      assert config.resource_limits.max_memory_mb == 512
      assert config.resource_limits.max_cpu_percent == 80
      assert config.resource_limits.timeout_ms == 300_000
    end

    test "creates config with allowed paths" do
      working_dir = System.tmp_dir!()
      {:ok, config} = SandboxConfig.new(working_dir, allowed_paths: ["lib", "test"])

      assert length(config.allowed_paths) == 2
      assert Enum.any?(config.allowed_paths, &String.ends_with?(&1, "/lib"))
      assert Enum.any?(config.allowed_paths, &String.ends_with?(&1, "/test"))
    end

    test "creates config with environment variables" do
      working_dir = System.tmp_dir!()
      {:ok, config} = SandboxConfig.new(working_dir, env_vars: %{"FOO" => "bar"})

      assert config.env_vars == %{"FOO" => "bar"}
    end

    test "creates config with custom resource limits" do
      working_dir = System.tmp_dir!()

      {:ok, config} =
        SandboxConfig.new(working_dir,
          resource_limits: %{timeout_ms: 60_000, max_memory_mb: 256}
        )

      assert config.resource_limits.timeout_ms == 60_000
      assert config.resource_limits.max_memory_mb == 256
      assert config.resource_limits.max_cpu_percent == 80
    end

    test "expands working directory path" do
      {:ok, config} = SandboxConfig.new(".")

      assert config.working_dir == File.cwd!()
    end

    test "returns error for non-existent directory" do
      assert {:error, msg} = SandboxConfig.new("/nonexistent/directory/12345")
      assert String.contains?(msg, "does not exist")
    end

    test "returns error for non-string working_dir" do
      assert {:error, msg} = SandboxConfig.new(123)
      assert String.contains?(msg, "must be a string")
    end
  end

  describe "new!/2" do
    test "creates config successfully" do
      working_dir = System.tmp_dir!()
      config = SandboxConfig.new!(working_dir)

      assert %SandboxConfig{} = config
      assert config.working_dir == Path.expand(working_dir)
    end

    test "raises on invalid working directory" do
      assert_raise ArgumentError, fn ->
        SandboxConfig.new!("/nonexistent/directory/12345")
      end
    end
  end

  describe "default/0" do
    test "creates config with current working directory" do
      {:ok, config} = SandboxConfig.default()

      assert config.working_dir == File.cwd!()
      assert Enum.any?(config.allowed_paths, &String.ends_with?(&1, "/lib"))
      assert Enum.any?(config.allowed_paths, &String.ends_with?(&1, "/test"))
      assert Enum.any?(config.allowed_paths, &String.ends_with?(&1, "/config"))
    end
  end

  describe "with_limits/2" do
    test "updates resource limits" do
      {:ok, config} = SandboxConfig.new(System.tmp_dir!())
      updated = SandboxConfig.with_limits(config, timeout_ms: 10_000, max_memory_mb: 128)

      assert updated.resource_limits.timeout_ms == 10_000
      assert updated.resource_limits.max_memory_mb == 128
      assert updated.resource_limits.max_cpu_percent == 80
    end

    test "merges with existing limits" do
      {:ok, config} =
        SandboxConfig.new(System.tmp_dir!(), resource_limits: %{timeout_ms: 5_000})

      updated = SandboxConfig.with_limits(config, max_memory_mb: 256)

      assert updated.resource_limits.timeout_ms == 5_000
      assert updated.resource_limits.max_memory_mb == 256
    end
  end

  describe "allow_path/2" do
    test "adds path to allowed paths" do
      {:ok, config} = SandboxConfig.new(System.tmp_dir!())
      updated = SandboxConfig.allow_path(config, "extras")

      assert length(updated.allowed_paths) == 1
      assert List.first(updated.allowed_paths) =~ "/extras"
    end

    test "expands path relative to working_dir" do
      working_dir = System.tmp_dir!()
      {:ok, config} = SandboxConfig.new(working_dir)
      updated = SandboxConfig.allow_path(config, "data")

      assert List.first(updated.allowed_paths) == Path.join(working_dir, "data")
    end

    test "adds multiple paths" do
      {:ok, config} = SandboxConfig.new(System.tmp_dir!())

      updated =
        config
        |> SandboxConfig.allow_path("path1")
        |> SandboxConfig.allow_path("path2")

      assert length(updated.allowed_paths) == 2
    end
  end

  describe "with_env/2" do
    test "sets environment variables" do
      {:ok, config} = SandboxConfig.new(System.tmp_dir!())
      updated = SandboxConfig.with_env(config, %{"VAR1" => "value1"})

      assert updated.env_vars == %{"VAR1" => "value1"}
    end

    test "merges with existing environment variables" do
      {:ok, config} = SandboxConfig.new(System.tmp_dir!(), env_vars: %{"VAR1" => "value1"})
      updated = SandboxConfig.with_env(config, %{"VAR2" => "value2"})

      assert updated.env_vars == %{"VAR1" => "value1", "VAR2" => "value2"}
    end

    test "overwrites existing variables with same key" do
      {:ok, config} = SandboxConfig.new(System.tmp_dir!(), env_vars: %{"VAR1" => "old"})
      updated = SandboxConfig.with_env(config, %{"VAR1" => "new"})

      assert updated.env_vars == %{"VAR1" => "new"}
    end
  end
end
