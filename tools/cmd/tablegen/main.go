// Command tablegen turns the design spreadsheets in data_src/ into Godot
// resources under game/data/.
//
// The generated files are checked in, and `--check` fails when a resource is
// stale, so CI can prove that data_src and game/data agree.
package main

import (
	"encoding/csv"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

func main() {
	root := flag.String("root", ".", "repository root")
	check := flag.Bool("check", false, "verify generated files are up to date instead of writing")
	flag.Parse()

	if err := run(*root, *check); err != nil {
		fmt.Fprintln(os.Stderr, "tablegen:", err)
		os.Exit(1)
	}
}

type table struct {
	name   string // file name without extension
	header []string
	rows   [][]string
}

func run(root string, check bool) error {
	srcDir := filepath.Join(root, "data_src")
	outDir := filepath.Join(root, "game", "data")
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return err
	}

	generators := []struct {
		file   string
		script string
		build  func(t table) (string, error)
	}{
		{"materials.csv", "materials", buildMaterials},
		{"fuels.csv", "fuels", buildFuels},
		{"difficulty.csv", "difficulty", buildDifficulty},
	}

	stale := false
	for _, g := range generators {
		t, err := readTable(filepath.Join(srcDir, g.file))
		if err != nil {
			return err
		}
		out, err := g.build(t)
		if err != nil {
			return fmt.Errorf("%s: %w", g.file, err)
		}
		path := filepath.Join(outDir, g.script+".tres")
		if check {
			old, err := os.ReadFile(path)
			if err != nil || string(old) != out {
				stale = true
				fmt.Printf("stale: %s\n", path)
			}
			continue
		}
		if err := os.WriteFile(path, []byte(out), 0o644); err != nil {
			return err
		}
		fmt.Printf("wrote %s (%d rows)\n", path, len(t.rows))
	}
	if stale {
		return fmt.Errorf("generated resources are out of date, run tools/tablegen")
	}
	return nil
}

func readTable(path string) (table, error) {
	f, err := os.Open(path)
	if err != nil {
		return table{}, err
	}
	defer f.Close()

	r := csv.NewReader(f)
	r.TrimLeadingSpace = true
	r.Comment = '#'
	header, err := r.Read()
	if err != nil {
		return table{}, err
	}
	for i := range header {
		header[i] = strings.TrimSpace(header[i])
	}
	t := table{name: strings.TrimSuffix(filepath.Base(path), ".csv"), header: header}
	for {
		rec, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return table{}, err
		}
		if len(rec) != len(header) {
			return table{}, fmt.Errorf("%s: row %d has %d fields, want %d", path, len(t.rows)+2, len(rec), len(header))
		}
		t.rows = append(t.rows, rec)
	}
	if len(t.rows) == 0 {
		return table{}, fmt.Errorf("%s: no data rows", path)
	}
	return t, nil
}

func (t table) col(name string) int {
	for i, h := range t.header {
		if h == name {
			return i
		}
	}
	return -1
}

func (t table) require(cols ...string) error {
	var missing []string
	for _, c := range cols {
		if t.col(c) < 0 {
			missing = append(missing, c)
		}
	}
	if len(missing) > 0 {
		return fmt.Errorf("%s.csv: missing column(s) %s", t.name, strings.Join(missing, ", "))
	}
	return nil
}

// gdString escapes a value for use inside a Godot string literal.
func gdString(s string) string {
	r := strings.NewReplacer(`\`, `\\`, `"`, `\"`)
	return `"` + r.Replace(s) + `"`
}

func f32(s string) (string, error) {
	v, err := strconv.ParseFloat(strings.TrimSpace(s), 32)
	if err != nil {
		return "", fmt.Errorf("not a number: %q", s)
	}
	return strconv.FormatFloat(v, 'f', -1, 32), nil
}

func integer(s string) (int, error) {
	return strconv.Atoi(strings.TrimSpace(s))
}

func boolean(s string) (string, error) {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "true", "1", "yes":
		return "true", nil
	case "false", "0", "no":
		return "false", nil
	}
	return "", fmt.Errorf("not a boolean: %q", s)
}

// resourceHeader renders the Godot resource header for a table script and the
// row script its entries are instances of.
func resourceHeader(scriptClass, scriptPath, rowPath string) string {
	return fmt.Sprintf("[gd_resource type=\"Resource\" script_class=%s load_steps=3 format=3]\n\n"+
		"[ext_resource type=\"Script\" path=\"res://%s\" id=\"1_script\"]\n"+
		"[ext_resource type=\"Script\" path=\"res://%s\" id=\"2_row\"]\n\n",
		gdString(scriptClass), scriptPath, rowPath)
}

// resourceBody renders a block of `[resource]` properties.
func resourceBody(props []string) string {
	return "[resource]\n" + strings.Join(props, "\n") + "\n"
}

// subResourceBlock renders one `[sub_resource type="Resource" id="..."]` block.
// `scriptRef` is the ExtResource("1_script") reference: writing it into the
// sub-resource is what makes the stored objects instances of the GDScript
// class, which the typed arrays in the tables require.
func subResourceBlock(scriptName string, scriptRef string, props []string) string {
	lines := append([]string{"script = " + scriptRef}, props...)
	return "[sub_resource type=\"Resource\" id=" + gdString(scriptName) + "]\n" + strings.Join(lines, "\n") + "\n"
}

// arrayOfResources renders an Array[ExtResource("1_script")] literal.
func arrayOfResources(ids []string) string {
	return "Array[ExtResource(\"2_row\")]([" + strings.Join(ids, ", ") + "])"
}

func buildMaterials(t table) (string, error) {
	if err := t.require("id", "name", "conductance_w_per_k", "heat_capacity_j_per_k", "surface_coef_w_per_k", "blocks_wind"); err != nil {
		return "", err
	}
	scriptRef := "ExtResource(\"2_row\")"
	ids := make([]string, 0, len(t.rows))
	var blocks []string
	seen := map[int]bool{}
	rows := append([][]string(nil), t.rows...)
	sort.SliceStable(rows, func(i, j int) bool {
		a, _ := integer(rows[i][t.col("id")])
		b, _ := integer(rows[j][t.col("id")])
		return a < b
	})
	for _, row := range rows {
		id, err := integer(row[t.col("id")])
		if err != nil {
			return "", err
		}
		if seen[id] {
			return "", fmt.Errorf("duplicate material id %d", id)
		}
		seen[id] = true
		strings_ := []string{
			"id = " + strconv.Itoa(id),
			"id_name = " + gdString(strings.TrimSpace(row[t.col("name")])),
		}
		for _, pair := range [][2]string{
			{"conductance_w_per_k", "conductance_w_per_k"},
			{"heat_capacity_j_per_k", "heat_capacity_j_per_k"},
			{"surface_coef_w_per_k", "surface_coef_w_per_k"},
		} {
			v, err := f32(row[t.col(pair[0])])
			if err != nil {
				return "", fmt.Errorf("material %d: %w", id, err)
			}
			strings_ = append(strings_, pair[1]+" = "+v)
		}
		b, err := boolean(row[t.col("blocks_wind")])
		if err != nil {
			return "", fmt.Errorf("material %d: %w", id, err)
		}
		strings_ = append(strings_, "blocks_wind = "+b)
		blockID := fmt.Sprintf("mat_%d", id)
		ids = append(ids, "SubResource("+gdString(blockID)+")")
		blocks = append(blocks, subResourceBlock(blockID, scriptRef, strings_))
	}

	props := []string{"script = ExtResource(\"1_script\")", "materials = " + arrayOfResources(ids)}
	out := resourceHeader("MaterialTable", "systems/thermal/material_table.gd", "systems/thermal/material_def.gd")
	out += strings.Join(blocks, "\n")
	out += "\n" + resourceBody(props)
	return out, nil
}

func buildFuels(t table) (string, error) {
	if err := t.require("id", "display_name", "heat_value_kj_per_kg", "mass_kg", "burn_minutes", "ignition_temp_c"); err != nil {
		return "", err
	}
	scriptRef := "ExtResource(\"2_row\")"
	ids := make([]string, 0, len(t.rows))
	var blocks []string
	for _, row := range t.rows {
		id := strings.TrimSpace(row[t.col("id")])
		if id == "" {
			return "", fmt.Errorf("empty fuel id")
		}
		props := []string{"id = " + gdString(id), "display_name = " + gdString(strings.TrimSpace(row[t.col("display_name")]))}
		for _, pair := range [][2]string{
			{"heat_value_kj_per_kg", "heat_value_kj_per_kg"},
			{"mass_kg", "mass_kg"},
			{"burn_minutes", "burn_minutes"},
			{"ignition_temp_c", "ignition_temp_c"},
		} {
			v, err := f32(row[t.col(pair[0])])
			if err != nil {
				return "", fmt.Errorf("fuel %s: %w", id, err)
			}
			props = append(props, pair[1]+" = "+v)
		}
		if i := t.col("note"); i >= 0 {
			props = append(props, "note = "+gdString(strings.TrimSpace(row[i])))
		}
		blockID := "fuel_" + id
		ids = append(ids, "SubResource("+gdString(blockID)+")")
		blocks = append(blocks, subResourceBlock(blockID, scriptRef, props))
	}
	props := []string{"script = ExtResource(\"1_script\")", "fuels = " + arrayOfResources(ids)}
	out := resourceHeader("FuelTable", "systems/fuel/fuel_table.gd", "systems/fuel/fuel_def.gd")
	out += strings.Join(blocks, "\n")
	out += "\n" + resourceBody(props)
	return out, nil
}

func buildDifficulty(t table) (string, error) {
	if err := t.require("id", "display_name", "cooling_rate_mult", "resource_mult", "forecast_error_c", "event_frequency_mult", "save_mode"); err != nil {
		return "", err
	}
	scriptRef := "ExtResource(\"2_row\")"
	ids := make([]string, 0, len(t.rows))
	var blocks []string
	for _, row := range t.rows {
		id := strings.TrimSpace(row[t.col("id")])
		if id == "" {
			return "", fmt.Errorf("empty difficulty id")
		}
		props := []string{"id = " + gdString(id), "display_name = " + gdString(strings.TrimSpace(row[t.col("display_name")]))}
		for _, pair := range [][2]string{
			{"cooling_rate_mult", "cooling_rate_mult"},
			{"resource_mult", "resource_mult"},
			{"forecast_error_c", "forecast_error_c"},
			{"event_frequency_mult", "event_frequency_mult"},
		} {
			v, err := f32(row[t.col(pair[0])])
			if err != nil {
				return "", fmt.Errorf("difficulty %s: %w", id, err)
			}
			props = append(props, pair[1]+" = "+v)
		}
		props = append(props, "save_mode = "+gdString(strings.TrimSpace(row[t.col("save_mode")])))
		blockID := "diff_" + id
		ids = append(ids, "SubResource("+gdString(blockID)+")")
		blocks = append(blocks, subResourceBlock(blockID, scriptRef, props))
	}
	props := []string{"script = ExtResource(\"1_script\")", "profiles = " + arrayOfResources(ids)}
	out := resourceHeader("DifficultyTable", "modes/difficulty_table.gd", "modes/difficulty_profile.gd")
	out += strings.Join(blocks, "\n")
	out += "\n" + resourceBody(props)
	return out, nil
}
