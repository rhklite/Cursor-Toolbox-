---
name: Add Equations to Graph
overview: Update the Python script to render the mathematical equations on the left side of the graph, mimicking the Desmos UI from the original screenshot.
todos:
  - id: adjust-layout
    content: Update Python script to adjust figure layout for left panel
    status: completed
  - id: add-equations
    content: Add LaTeX text annotations and color markers for equations
    status: completed
  - id: regenerate-image
    content: Run script to regenerate gaussian_graph.png
    status: completed
isProject: false
---

# Add Equations to Graph

1. **Adjust Figure Layout**: Modify the `matplotlib` script to increase the figure width and adjust the left margin (e.g., using `plt.subplots_adjust(left=0.3)`) to create a dedicated panel space for the equations.
2. **Render Equations**: Use `fig.text` to place LaTeX-formatted equations on the left side of the figure. The equations will be:
  - $y = e^{-1(0.5 - x)^2}$
  - $y = e^{-1(0.9 - x)^2}$
  - $x = 0.5$
  - $x = 0.9$
3. **Add Color Indicators**: Draw colored markers (circles or wave icons) next to each equation to match the plotted curves and lines (Green, Black, Red, Blue).
4. **Regenerate Image**: Run the updated script to overwrite `gaussian_graph.png` with the new layout.

