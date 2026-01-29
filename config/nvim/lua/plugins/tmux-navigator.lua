return {
  "christoomey/vim-tmux-navigator",
  -- Load this plugin at startup, as it's for core navigation
  lazy = false,
  keys = {
    {
      "<C-h>",
      "<cmd>TmuxNavigateLeft<cr>",
      desc = "Pane/Window: Navigate Left",
    },
    {
      "<C-j>",
      "<cmd>TmuxNavigateDown<cr>",
      desc = "Pane/Window: Navigate Down",
    },
    {
      "<C-k>",
      "<cmd>TmuxNavigateUp<cr>",
      desc = "Pane/Window: Navigate Up",
    },
    {
      "<C-l>",
      "<cmd>TmuxNavigateRight<cr>",
      desc = "Pane/Window: Navigate Right",
    },
  },
}